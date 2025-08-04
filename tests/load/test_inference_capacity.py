#!/usr/bin/env python3
"""
Load testing for inference service capacity validation
Tests concurrent request handling, auto-scaling behavior, and performance under load
"""

import time
import json
import os
import sys
import asyncio
import aiohttp
import threading
import queue
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import numpy as np
import pandas as pd
from concurrent.futures import ThreadPoolExecutor, as_completed
import logging
from dataclasses import dataclass
import statistics

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class LoadTestConfig:
    """Configuration for load testing"""
    base_url: str = "http://localhost:8000"
    max_concurrent_users: int = 100
    test_duration_seconds: int = 300  # 5 minutes
    ramp_up_seconds: int = 60  # 1 minute ramp-up
    request_timeout_seconds: int = 30
    target_rps: int = 1000  # Requests per second
    batch_sizes: List[int] = None
    
    def __post_init__(self):
        if self.batch_sizes is None:
            self.batch_sizes = [1, 10, 50, 100]

@dataclass
class RequestResult:
    """Result of a single request"""
    timestamp: datetime
    response_time_ms: float
    status_code: int
    success: bool
    error_message: Optional[str] = None
    request_type: str = "single"
    batch_size: int = 1

class LoadTestMetrics:
    """Metrics collection for load testing"""
    
    def __init__(self):
        self.results: List[RequestResult] = []
        self.start_time: Optional[datetime] = None
        self.end_time: Optional[datetime] = None
        self._lock = threading.Lock()
    
    def add_result(self, result: RequestResult):
        """Add a request result"""
        with self._lock:
            self.results.append(result)
    
    def start_test(self):
        """Mark test start time"""
        self.start_time = datetime.now()
    
    def end_test(self):
        """Mark test end time"""
        self.end_time = datetime.now()
    
    def get_summary(self) -> Dict:
        """Get test summary statistics"""
        if not self.results:
            return {}
        
        successful_results = [r for r in self.results if r.success]
        failed_results = [r for r in self.results if not r.success]
        
        response_times = [r.response_time_ms for r in successful_results]
        
        if not response_times:
            return {
                'total_requests': len(self.results),
                'successful_requests': 0,
                'failed_requests': len(failed_results),
                'success_rate': 0.0,
                'error_rate': 100.0
            }
        
        # Calculate time-based metrics
        test_duration = (self.end_time - self.start_time).total_seconds() if self.end_time and self.start_time else 0
        
        summary = {
            'total_requests': len(self.results),
            'successful_requests': len(successful_results),
            'failed_requests': len(failed_results),
            'success_rate': (len(successful_results) / len(self.results)) * 100,
            'error_rate': (len(failed_results) / len(self.results)) * 100,
            'test_duration_seconds': test_duration,
            'requests_per_second': len(self.results) / test_duration if test_duration > 0 else 0,
            'successful_rps': len(successful_results) / test_duration if test_duration > 0 else 0,
            'response_time_stats': {
                'mean_ms': statistics.mean(response_times),
                'median_ms': statistics.median(response_times),
                'min_ms': min(response_times),
                'max_ms': max(response_times),
                'p95_ms': np.percentile(response_times, 95),
                'p99_ms': np.percentile(response_times, 99),
                'std_dev_ms': statistics.stdev(response_times) if len(response_times) > 1 else 0
            }
        }
        
        # Status code distribution
        status_codes = {}
        for result in self.results:
            status_codes[result.status_code] = status_codes.get(result.status_code, 0) + 1
        summary['status_code_distribution'] = status_codes
        
        # Error analysis
        if failed_results:
            error_types = {}
            for result in failed_results:
                error_msg = result.error_message or f"HTTP {result.status_code}"
                error_types[error_msg] = error_types.get(error_msg, 0) + 1
            summary['error_types'] = error_types
        
        return summary

class InferenceLoadTester:
    """Load tester for inference service"""
    
    def __init__(self, config: LoadTestConfig):
        self.config = config
        self.metrics = LoadTestMetrics()
        self.session: Optional[aiohttp.ClientSession] = None
    
    def generate_test_transaction(self) -> Dict:
        """Generate a test transaction for inference"""
        return {
            "TX_AMOUNT": np.random.uniform(1, 1000),
            "yyyy": 2024,
            "mm": np.random.randint(1, 13),
            "dd": np.random.randint(1, 29),
            "CUSTOMER_ID_index": float(np.random.randint(1, 10000)),
            "TERMINAL_ID_index": float(np.random.randint(1, 1000)),
            "customer_id_nb_txns_15min_window": float(np.random.randint(1, 20)),
            "customer_id_avg_amt_15min_window": np.random.uniform(50, 500),
            "terminal_id_nb_txns_15min_window": float(np.random.randint(5, 50)),
            "terminal_id_avg_amt_15min_window": np.random.uniform(100, 800),
            "customer_id_nb_txns_1day_window": float(np.random.randint(1, 100)),
            "customer_id_avg_amt_1day_window": np.random.uniform(50, 500)
        }
    
    async def make_single_prediction_request(self) -> RequestResult:
        """Make a single prediction request"""
        transaction = self.generate_test_transaction()
        start_time = time.time()
        
        try:
            async with self.session.post(
                f"{self.config.base_url}/predict",
                json=transaction,
                timeout=aiohttp.ClientTimeout(total=self.config.request_timeout_seconds)
            ) as response:
                await response.text()  # Read response body
                end_time = time.time()
                
                return RequestResult(
                    timestamp=datetime.now(),
                    response_time_ms=(end_time - start_time) * 1000,
                    status_code=response.status,
                    success=response.status == 200,
                    error_message=None if response.status == 200 else f"HTTP {response.status}",
                    request_type="single",
                    batch_size=1
                )
        
        except asyncio.TimeoutError:
            return RequestResult(
                timestamp=datetime.now(),
                response_time_ms=(time.time() - start_time) * 1000,
                status_code=408,
                success=False,
                error_message="Request timeout",
                request_type="single",
                batch_size=1
            )
        except Exception as e:
            return RequestResult(
                timestamp=datetime.now(),
                response_time_ms=(time.time() - start_time) * 1000,
                status_code=0,
                success=False,
                error_message=str(e),
                request_type="single",
                batch_size=1
            )
    
    async def make_batch_prediction_request(self, batch_size: int) -> RequestResult:
        """Make a batch prediction request"""
        transactions = [self.generate_test_transaction() for _ in range(batch_size)]
        batch_data = {"transactions": transactions}
        start_time = time.time()
        
        try:
            async with self.session.post(
                f"{self.config.base_url}/predict/batch",
                json=batch_data,
                timeout=aiohttp.ClientTimeout(total=self.config.request_timeout_seconds)
            ) as response:
                await response.text()  # Read response body
                end_time = time.time()
                
                return RequestResult(
                    timestamp=datetime.now(),
                    response_time_ms=(end_time - start_time) * 1000,
                    status_code=response.status,
                    success=response.status == 200,
                    error_message=None if response.status == 200 else f"HTTP {response.status}",
                    request_type="batch",
                    batch_size=batch_size
                )
        
        except asyncio.TimeoutError:
            return RequestResult(
                timestamp=datetime.now(),
                response_time_ms=(time.time() - start_time) * 1000,
                status_code=408,
                success=False,
                error_message="Request timeout",
                request_type="batch",
                batch_size=batch_size
            )
        except Exception as e:
            return RequestResult(
                timestamp=datetime.now(),
                response_time_ms=(time.time() - start_time) * 1000,
                status_code=0,
                success=False,
                error_message=str(e),
                request_type="batch",
                batch_size=batch_size
            )
    
    async def health_check(self) -> bool:
        """Check if the service is healthy"""
        try:
            async with self.session.get(
                f"{self.config.base_url}/health",
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    return data.get('status') == 'healthy'
                return False
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False
    
    async def run_constant_load_test(self, rps: int, duration_seconds: int) -> List[RequestResult]:
        """Run constant load test with specified RPS"""
        logger.info(f"Running constant load test: {rps} RPS for {duration_seconds} seconds")
        
        results = []
        start_time = time.time()
        request_interval = 1.0 / rps
        
        async def make_request():
            result = await self.make_single_prediction_request()
            results.append(result)
            self.metrics.add_result(result)
        
        # Schedule requests
        tasks = []
        next_request_time = start_time
        
        while time.time() - start_time < duration_seconds:
            current_time = time.time()
            
            if current_time >= next_request_time:
                task = asyncio.create_task(make_request())
                tasks.append(task)
                next_request_time += request_interval
            
            # Clean up completed tasks
            tasks = [task for task in tasks if not task.done()]
            
            # Small sleep to prevent busy waiting
            await asyncio.sleep(0.001)
        
        # Wait for remaining tasks
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        
        logger.info(f"Constant load test completed: {len(results)} requests made")
        return results
    
    async def run_ramp_up_test(self, max_rps: int, ramp_duration_seconds: int) -> List[RequestResult]:
        """Run ramp-up load test"""
        logger.info(f"Running ramp-up test: 0 to {max_rps} RPS over {ramp_duration_seconds} seconds")
        
        results = []
        start_time = time.time()
        
        while time.time() - start_time < ramp_duration_seconds:
            elapsed = time.time() - start_time
            current_rps = int((elapsed / ramp_duration_seconds) * max_rps)
            
            if current_rps > 0:
                # Run for 1 second at current RPS
                batch_results = await self.run_constant_load_test(current_rps, 1)
                results.extend(batch_results)
        
        logger.info(f"Ramp-up test completed: {len(results)} requests made")
        return results
    
    async def run_batch_size_test(self) -> Dict[int, List[RequestResult]]:
        """Test different batch sizes"""
        logger.info("Running batch size performance test")
        
        batch_results = {}
        
        for batch_size in self.config.batch_sizes:
            logger.info(f"Testing batch size: {batch_size}")
            
            results = []
            num_requests = 50  # Test with 50 requests per batch size
            
            for _ in range(num_requests):
                result = await self.make_batch_prediction_request(batch_size)
                results.append(result)
                self.metrics.add_result(result)
                
                # Small delay between requests
                await asyncio.sleep(0.1)
            
            batch_results[batch_size] = results
            
            # Calculate and log batch performance
            successful_results = [r for r in results if r.success]
            if successful_results:
                avg_response_time = statistics.mean([r.response_time_ms for r in successful_results])
                avg_throughput = sum(r.batch_size for r in successful_results) / (num_requests * 0.1)  # Approximate
                
                logger.info(f"Batch size {batch_size}: {avg_response_time:.2f}ms avg response time, ~{avg_throughput:.0f} predictions/sec")
        
        return batch_results
    
    async def run_stress_test(self, max_concurrent: int, duration_seconds: int) -> List[RequestResult]:
        """Run stress test with maximum concurrent requests"""
        logger.info(f"Running stress test: {max_concurrent} concurrent users for {duration_seconds} seconds")
        
        results = []
        start_time = time.time()
        
        async def user_session():
            """Simulate a user session with multiple requests"""
            session_results = []
            session_start = time.time()
            
            while time.time() - session_start < duration_seconds:
                result = await self.make_single_prediction_request()
                session_results.append(result)
                self.metrics.add_result(result)
                
                # Random delay between requests (0.1 to 2 seconds)
                await asyncio.sleep(np.random.uniform(0.1, 2.0))
            
            return session_results
        
        # Create concurrent user sessions
        tasks = [asyncio.create_task(user_session()) for _ in range(max_concurrent)]
        
        # Wait for all sessions to complete
        session_results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Flatten results
        for session_result in session_results:
            if isinstance(session_result, list):
                results.extend(session_result)
        
        logger.info(f"Stress test completed: {len(results)} requests made")
        return results
    
    async def run_spike_test(self, normal_rps: int, spike_rps: int, spike_duration: int) -> List[RequestResult]:
        """Run spike test with sudden load increase"""
        logger.info(f"Running spike test: {normal_rps} RPS with spike to {spike_rps} RPS for {spike_duration}s")
        
        results = []
        
        # Normal load for 30 seconds
        logger.info("Phase 1: Normal load")
        normal_results = await self.run_constant_load_test(normal_rps, 30)
        results.extend(normal_results)
        
        # Spike load
        logger.info("Phase 2: Spike load")
        spike_results = await self.run_constant_load_test(spike_rps, spike_duration)
        results.extend(spike_results)
        
        # Return to normal load for 30 seconds
        logger.info("Phase 3: Return to normal load")
        recovery_results = await self.run_constant_load_test(normal_rps, 30)
        results.extend(recovery_results)
        
        logger.info(f"Spike test completed: {len(results)} requests made")
        return results
    
    async def run_full_load_test_suite(self) -> Dict:
        """Run complete load test suite"""
        logger.info("Starting full load test suite")
        
        # Initialize session
        connector = aiohttp.TCPConnector(limit=1000, limit_per_host=100)
        self.session = aiohttp.ClientSession(connector=connector)
        
        try:
            # Health check
            logger.info("Performing initial health check...")
            if not await self.health_check():
                logger.error("Service health check failed. Aborting load tests.")
                return {"error": "Service not healthy"}
            
            self.metrics.start_test()
            
            test_results = {}
            
            # Test 1: Constant load test
            logger.info("\n" + "="*50)
            logger.info("Test 1: Constant Load Test")
            logger.info("="*50)
            constant_load_results = await self.run_constant_load_test(50, 60)  # 50 RPS for 1 minute
            test_results['constant_load'] = constant_load_results
            
            # Test 2: Ramp-up test
            logger.info("\n" + "="*50)
            logger.info("Test 2: Ramp-up Test")
            logger.info("="*50)
            ramp_up_results = await self.run_ramp_up_test(100, 60)  # Ramp to 100 RPS over 1 minute
            test_results['ramp_up'] = ramp_up_results
            
            # Test 3: Batch size test
            logger.info("\n" + "="*50)
            logger.info("Test 3: Batch Size Test")
            logger.info("="*50)
            batch_results = await self.run_batch_size_test()
            test_results['batch_sizes'] = batch_results
            
            # Test 4: Stress test
            logger.info("\n" + "="*50)
            logger.info("Test 4: Stress Test")
            logger.info("="*50)
            stress_results = await self.run_stress_test(20, 60)  # 20 concurrent users for 1 minute
            test_results['stress'] = stress_results
            
            # Test 5: Spike test
            logger.info("\n" + "="*50)
            logger.info("Test 5: Spike Test")
            logger.info("="*50)
            spike_results = await self.run_spike_test(30, 150, 30)  # Spike from 30 to 150 RPS
            test_results['spike'] = spike_results
            
            self.metrics.end_test()
            
            # Generate comprehensive report
            summary = self.metrics.get_summary()
            
            final_results = {
                'config': {
                    'base_url': self.config.base_url,
                    'max_concurrent_users': self.config.max_concurrent_users,
                    'test_duration_seconds': self.config.test_duration_seconds,
                    'target_rps': self.config.target_rps
                },
                'summary': summary,
                'detailed_results': test_results,
                'recommendations': self._generate_recommendations(summary)
            }
            
            return final_results
        
        finally:
            if self.session:
                await self.session.close()
    
    def _generate_recommendations(self, summary: Dict) -> List[str]:
        """Generate performance recommendations based on test results"""
        recommendations = []
        
        if summary.get('success_rate', 0) < 95:
            recommendations.append("Success rate is below 95%. Consider investigating error causes and improving error handling.")
        
        response_stats = summary.get('response_time_stats', {})
        if response_stats.get('p95_ms', 0) > 1000:
            recommendations.append("95th percentile response time exceeds 1 second. Consider optimizing inference performance.")
        
        if response_stats.get('mean_ms', 0) > 500:
            recommendations.append("Mean response time exceeds 500ms. Consider scaling up resources or optimizing model inference.")
        
        if summary.get('successful_rps', 0) < self.config.target_rps * 0.8:
            recommendations.append(f"Achieved RPS is below 80% of target ({self.config.target_rps}). Consider horizontal scaling.")
        
        error_rate = summary.get('error_rate', 0)
        if error_rate > 5:
            recommendations.append(f"Error rate is {error_rate:.1f}%, which is above acceptable threshold of 5%.")
        
        if not recommendations:
            recommendations.append("Performance looks good! All metrics are within acceptable ranges.")
        
        return recommendations

def main():
    """Main load testing execution"""
    config = LoadTestConfig(
        base_url=os.getenv('INFERENCE_SERVICE_URL', 'http://localhost:8000'),
        max_concurrent_users=50,
        test_duration_seconds=300,
        target_rps=100,
        batch_sizes=[1, 5, 10, 25, 50]
    )
    
    async def run_tests():
        tester = InferenceLoadTester(config)
        results = await tester.run_full_load_test_suite()
        
        # Save results
        output_dir = 'tests/reports/load'
        os.makedirs(output_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        results_file = os.path.join(output_dir, f'load_test_results_{timestamp}.json')
        
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        # Print summary
        if 'error' not in results:
            summary = results['summary']
            logger.info("\n" + "="*60)
            logger.info("LOAD TEST SUMMARY")
            logger.info("="*60)
            logger.info(f"Total Requests: {summary['total_requests']:,}")
            logger.info(f"Successful Requests: {summary['successful_requests']:,}")
            logger.info(f"Success Rate: {summary['success_rate']:.2f}%")
            logger.info(f"Average RPS: {summary['requests_per_second']:.2f}")
            logger.info(f"Successful RPS: {summary['successful_rps']:.2f}")
            
            response_stats = summary['response_time_stats']
            logger.info(f"\nResponse Time Statistics:")
            logger.info(f"  Mean: {response_stats['mean_ms']:.2f}ms")
            logger.info(f"  Median: {response_stats['median_ms']:.2f}ms")
            logger.info(f"  95th Percentile: {response_stats['p95_ms']:.2f}ms")
            logger.info(f"  99th Percentile: {response_stats['p99_ms']:.2f}ms")
            logger.info(f"  Max: {response_stats['max_ms']:.2f}ms")
            
            logger.info(f"\nRecommendations:")
            for i, rec in enumerate(results['recommendations'], 1):
                logger.info(f"  {i}. {rec}")
        
        logger.info(f"\nDetailed results saved to: {results_file}")
        
        return results
    
    # Run the async tests
    return asyncio.run(run_tests())

if __name__ == "__main__":
    main()