#!/usr/bin/env python3
"""
Performance Optimization Analyzer

This script analyzes actual usage patterns and provides optimization recommendations
for the EMR to EKS migration infrastructure.
"""

import os
import json
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Any
import boto3
import pandas as pd
import numpy as np
from kubernetes import client, config

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class PerformanceOptimizationAnalyzer:
    """Analyzes performance and provides optimization recommendations"""
    
    def __init__(self, region: str = 'us-west-2'):
        self.region = region
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        
        # Initialize Kubernetes client
        try:
            config.load_incluster_config()
        except:
            try:
                config.load_kube_config()
            except:
                logger.warning("Could not load Kubernetes config - using mock data")
        
        self.k8s_core_v1 = client.CoreV1Api()
        self.k8s_metrics = client.CustomObjectsApi()
        
    def analyze_gpu_utilization_patterns(self) -> Dict[str, Any]:
        """Analyze GPU utilization patterns and identify optimization opportunities"""
        logger.info("🔍 Analyzing GPU utilization patterns...")
        
        # Mock GPU utilization data (in production, this would come from DCGM exporter)
        gpu_metrics = {
            'average_utilization': 68.5,
            'peak_utilization': 95.2,
            'idle_time_percentage': 25.3,
            'memory_utilization': 72.1,
            'power_consumption_watts': 180.5,
            'temperature_celsius': 65.2
        }
        
        # Analyze patterns
        analysis = {
            'utilization_efficiency': gpu_metrics['average_utilization'] / 100,
            'idle_waste_cost_per_hour': (gpu_metrics['idle_time_percentage'] / 100) * 1.20,  # $1.20/hour for g5.2xlarge
            'optimization_potential': max(0, 85 - gpu_metrics['average_utilization']),
            'memory_efficiency': gpu_metrics['memory_utilization'] / 100,
            'thermal_efficiency': max(0, 80 - gpu_metrics['temperature_celsius']) / 80
        }
        
        recommendations = []
        
        if gpu_metrics['average_utilization'] < 70:
            recommendations.append({
                'type': 'resource_rightsizing',
                'description': 'Consider using smaller GPU instances or implementing GPU sharing',
                'potential_savings': f"{analysis['idle_waste_cost_per_hour']:.2f} $/hour"
            })
        
        if gpu_metrics['idle_time_percentage'] > 20:
            recommendations.append({
                'type': 'workload_scheduling',
                'description': 'Implement better workload scheduling to reduce idle time',
                'potential_savings': f"{gpu_metrics['idle_time_percentage']:.1f}% cost reduction"
            })
        
        if gpu_metrics['memory_utilization'] < 60:
            recommendations.append({
                'type': 'memory_optimization',
                'description': 'Optimize memory usage or consider instances with less GPU memory',
                'potential_savings': '15-20% cost reduction'
            })
        
        return {
            'metrics': gpu_metrics,
            'analysis': analysis,
            'recommendations': recommendations,
            'optimization_score': self._calculate_gpu_optimization_score(analysis)
        }
    
    def analyze_cpu_memory_patterns(self) -> Dict[str, Any]:
        """Analyze CPU and memory utilization patterns"""
        logger.info("💾 Analyzing CPU and memory utilization patterns...")
        
        # Mock CPU/Memory metrics (in production, this would come from Prometheus)
        cpu_memory_metrics = {
            'cpu_utilization': {
                'average': 45.2,
                'peak': 78.5,
                'p95': 65.3,
                'requests_vs_usage_ratio': 0.6  # Using 60% of requested CPU
            },
            'memory_utilization': {
                'average': 52.8,
                'peak': 82.1,
                'p95': 71.4,
                'requests_vs_usage_ratio': 0.65  # Using 65% of requested memory
            },
            'node_utilization': {
                'average_nodes_active': 8,
                'peak_nodes_active': 15,
                'total_nodes_provisioned': 20
            }
        }
        
        # Analyze patterns
        analysis = {
            'cpu_efficiency': cpu_memory_metrics['cpu_utilization']['requests_vs_usage_ratio'],
            'memory_efficiency': cpu_memory_metrics['memory_utilization']['requests_vs_usage_ratio'],
            'node_efficiency': cpu_memory_metrics['node_utilization']['average_nodes_active'] / cpu_memory_metrics['node_utilization']['total_nodes_provisioned'],
            'overprovisioning_waste': {
                'cpu': (1 - cpu_memory_metrics['cpu_utilization']['requests_vs_usage_ratio']) * 100,
                'memory': (1 - cpu_memory_metrics['memory_utilization']['requests_vs_usage_ratio']) * 100
            }
        }
        
        recommendations = []
        
        if analysis['cpu_efficiency'] < 0.7:
            recommendations.append({
                'type': 'cpu_rightsizing',
                'description': f"Reduce CPU requests by {analysis['overprovisioning_waste']['cpu']:.1f}%",
                'potential_savings': f"{analysis['overprovisioning_waste']['cpu'] * 0.3:.1f}% cost reduction"
            })
        
        if analysis['memory_efficiency'] < 0.7:
            recommendations.append({
                'type': 'memory_rightsizing',
                'description': f"Reduce memory requests by {analysis['overprovisioning_waste']['memory']:.1f}%",
                'potential_savings': f"{analysis['overprovisioning_waste']['memory'] * 0.25:.1f}% cost reduction"
            })
        
        if analysis['node_efficiency'] < 0.6:
            recommendations.append({
                'type': 'cluster_rightsizing',
                'description': 'Optimize cluster auto-scaling parameters to reduce idle nodes',
                'potential_savings': f"{(1 - analysis['node_efficiency']) * 100:.1f}% infrastructure cost reduction"
            })
        
        return {
            'metrics': cpu_memory_metrics,
            'analysis': analysis,
            'recommendations': recommendations,
            'optimization_score': self._calculate_cpu_memory_optimization_score(analysis)
        }
    
    def analyze_storage_patterns(self) -> Dict[str, Any]:
        """Analyze storage utilization and cost patterns"""
        logger.info("💽 Analyzing storage utilization patterns...")
        
        # Mock storage metrics
        storage_metrics = {
            'ebs_volumes': {
                'total_provisioned_gb': 5000,
                'total_used_gb': 2800,
                'utilization_percentage': 56.0,
                'cost_per_month': 500.0
            },
            's3_storage': {
                'total_objects': 1500000,
                'total_size_gb': 12000,
                'intelligent_tiering_savings': 180.0,  # Monthly savings
                'lifecycle_policy_coverage': 75.0  # Percentage of data with lifecycle policies
            },
            'efs_storage': {
                'provisioned_throughput': 100,  # MB/s
                'average_throughput_used': 35,   # MB/s
                'cost_per_month': 150.0
            }
        }
        
        # Analyze patterns
        analysis = {
            'ebs_efficiency': storage_metrics['ebs_volumes']['utilization_percentage'] / 100,
            'ebs_overprovisioning': 100 - storage_metrics['ebs_volumes']['utilization_percentage'],
            's3_optimization_coverage': storage_metrics['s3_storage']['lifecycle_policy_coverage'] / 100,
            'efs_efficiency': storage_metrics['efs_storage']['average_throughput_used'] / storage_metrics['efs_storage']['provisioned_throughput']
        }
        
        recommendations = []
        
        if analysis['ebs_efficiency'] < 0.7:
            recommendations.append({
                'type': 'ebs_rightsizing',
                'description': f"Reduce EBS volume sizes by {analysis['ebs_overprovisioning']:.1f}%",
                'potential_savings': f"${analysis['ebs_overprovisioning'] * 5:.2f}/month"
            })
        
        if analysis['s3_optimization_coverage'] < 0.9:
            recommendations.append({
                'type': 's3_lifecycle_optimization',
                'description': 'Implement lifecycle policies for remaining data',
                'potential_savings': f"${(1 - analysis['s3_optimization_coverage']) * 200:.2f}/month"
            })
        
        if analysis['efs_efficiency'] < 0.5:
            recommendations.append({
                'type': 'efs_throughput_optimization',
                'description': 'Reduce provisioned throughput or switch to burst mode',
                'potential_savings': f"${(1 - analysis['efs_efficiency']) * 100:.2f}/month"
            })
        
        return {
            'metrics': storage_metrics,
            'analysis': analysis,
            'recommendations': recommendations,
            'optimization_score': self._calculate_storage_optimization_score(analysis)
        }
    
    def analyze_network_patterns(self) -> Dict[str, Any]:
        """Analyze network utilization and cost patterns"""
        logger.info("🌐 Analyzing network utilization patterns...")
        
        # Mock network metrics
        network_metrics = {
            'data_transfer': {
                'inbound_gb_per_month': 2500,
                'outbound_gb_per_month': 1800,
                'inter_az_transfer_gb': 500,
                'nat_gateway_cost_per_month': 120.0
            },
            'load_balancer': {
                'alb_cost_per_month': 80.0,
                'nlb_cost_per_month': 45.0,
                'average_connections': 1500,
                'peak_connections': 5000
            },
            'vpc_endpoints': {
                's3_endpoint_cost': 0,  # Gateway endpoint is free
                'other_endpoints_cost': 25.0,
                'data_processing_gb': 800
            }
        }
        
        # Analyze patterns
        analysis = {
            'inter_az_cost_impact': network_metrics['data_transfer']['inter_az_transfer_gb'] * 0.01,  # $0.01/GB
            'nat_gateway_efficiency': network_metrics['data_transfer']['outbound_gb_per_month'] / 1000,  # Efficiency metric
            'load_balancer_utilization': network_metrics['load_balancer']['average_connections'] / network_metrics['load_balancer']['peak_connections']
        }
        
        recommendations = []
        
        if network_metrics['data_transfer']['inter_az_transfer_gb'] > 300:
            recommendations.append({
                'type': 'inter_az_optimization',
                'description': 'Optimize data placement to reduce inter-AZ transfer costs',
                'potential_savings': f"${analysis['inter_az_cost_impact']:.2f}/month"
            })
        
        if analysis['load_balancer_utilization'] < 0.4:
            recommendations.append({
                'type': 'load_balancer_consolidation',
                'description': 'Consider consolidating load balancers for better utilization',
                'potential_savings': '$30-50/month'
            })
        
        if network_metrics['vpc_endpoints']['other_endpoints_cost'] > 20:
            recommendations.append({
                'type': 'vpc_endpoint_optimization',
                'description': 'Review VPC endpoint usage and optimize based on data transfer patterns',
                'potential_savings': f"${network_metrics['vpc_endpoints']['other_endpoints_cost'] * 0.2:.2f}/month"
            })
        
        return {
            'metrics': network_metrics,
            'analysis': analysis,
            'recommendations': recommendations,
            'optimization_score': self._calculate_network_optimization_score(analysis)
        }
    
    def analyze_workload_scheduling_patterns(self) -> Dict[str, Any]:
        """Analyze workload scheduling and resource allocation patterns"""
        logger.info("⏰ Analyzing workload scheduling patterns...")
        
        # Mock workload scheduling metrics
        scheduling_metrics = {
            'job_patterns': {
                'peak_hours': [9, 10, 11, 14, 15, 16],  # Hours of day
                'off_peak_utilization': 25.0,  # Percentage
                'batch_job_efficiency': 78.5,  # Percentage
                'interactive_job_efficiency': 65.2  # Percentage
            },
            'resource_contention': {
                'gpu_queue_time_avg_minutes': 8.5,
                'cpu_queue_time_avg_minutes': 2.1,
                'memory_pressure_events': 12,  # Per day
                'failed_scheduling_events': 3   # Per day
            },
            'auto_scaling': {
                'scale_up_time_avg_seconds': 45,
                'scale_down_time_avg_seconds': 180,
                'unnecessary_scale_events': 8,  # Per day
                'cost_of_over_provisioning': 85.0  # Per day
            }
        }
        
        # Analyze patterns
        analysis = {
            'peak_vs_offpeak_ratio': (100 - scheduling_metrics['job_patterns']['off_peak_utilization']) / scheduling_metrics['job_patterns']['off_peak_utilization'],
            'scheduling_efficiency': (scheduling_metrics['job_patterns']['batch_job_efficiency'] + scheduling_metrics['job_patterns']['interactive_job_efficiency']) / 2,
            'resource_contention_score': max(0, 100 - (scheduling_metrics['resource_contention']['gpu_queue_time_avg_minutes'] * 5)),
            'auto_scaling_efficiency': max(0, 100 - scheduling_metrics['auto_scaling']['unnecessary_scale_events'] * 5)
        }
        
        recommendations = []
        
        if scheduling_metrics['job_patterns']['off_peak_utilization'] < 40:
            recommendations.append({
                'type': 'workload_distribution',
                'description': 'Implement workload scheduling to better utilize off-peak hours',
                'potential_savings': f"${analysis['peak_vs_offpeak_ratio'] * 20:.2f}/day through spot instances"
            })
        
        if scheduling_metrics['resource_contention']['gpu_queue_time_avg_minutes'] > 5:
            recommendations.append({
                'type': 'gpu_resource_planning',
                'description': 'Increase GPU capacity or implement better job prioritization',
                'potential_impact': f"Reduce queue time by {scheduling_metrics['resource_contention']['gpu_queue_time_avg_minutes'] - 3:.1f} minutes"
            })
        
        if scheduling_metrics['auto_scaling']['unnecessary_scale_events'] > 5:
            recommendations.append({
                'type': 'auto_scaling_tuning',
                'description': 'Optimize auto-scaling parameters to reduce unnecessary scaling events',
                'potential_savings': f"${scheduling_metrics['auto_scaling']['cost_of_over_provisioning'] * 0.3:.2f}/day"
            })
        
        return {
            'metrics': scheduling_metrics,
            'analysis': analysis,
            'recommendations': recommendations,
            'optimization_score': self._calculate_scheduling_optimization_score(analysis)
        }
    
    def generate_cost_optimization_plan(self, all_analyses: Dict[str, Any]) -> Dict[str, Any]:
        """Generate comprehensive cost optimization plan"""
        logger.info("💰 Generating comprehensive cost optimization plan...")
        
        # Aggregate all recommendations
        all_recommendations = []
        total_optimization_score = 0
        
        for category, analysis in all_analyses.items():
            all_recommendations.extend(analysis.get('recommendations', []))
            total_optimization_score += analysis.get('optimization_score', 0)
        
        avg_optimization_score = total_optimization_score / len(all_analyses) if all_analyses else 0
        
        # Prioritize recommendations by impact and effort
        prioritized_recommendations = self._prioritize_recommendations(all_recommendations)
        
        # Calculate potential savings
        potential_savings = self._calculate_total_potential_savings(prioritized_recommendations)
        
        # Generate implementation timeline
        implementation_timeline = self._generate_implementation_timeline(prioritized_recommendations)
        
        optimization_plan = {
            'overall_optimization_score': avg_optimization_score,
            'total_recommendations': len(all_recommendations),
            'high_priority_recommendations': len([r for r in prioritized_recommendations if r.get('priority') == 'high']),
            'potential_monthly_savings': potential_savings['monthly_savings'],
            'potential_annual_savings': potential_savings['annual_savings'],
            'roi_timeline_months': potential_savings['roi_timeline_months'],
            'prioritized_recommendations': prioritized_recommendations[:10],  # Top 10
            'implementation_timeline': implementation_timeline,
            'quick_wins': [r for r in prioritized_recommendations if r.get('effort') == 'low' and r.get('impact') == 'high'][:5]
        }
        
        return optimization_plan
    
    def _calculate_gpu_optimization_score(self, analysis: Dict[str, float]) -> float:
        """Calculate GPU optimization score (0-100)"""
        utilization_score = analysis['utilization_efficiency'] * 40
        memory_score = analysis['memory_efficiency'] * 30
        thermal_score = analysis['thermal_efficiency'] * 20
        idle_score = max(0, 100 - analysis['optimization_potential']) * 0.1
        
        return min(100, utilization_score + memory_score + thermal_score + idle_score)
    
    def _calculate_cpu_memory_optimization_score(self, analysis: Dict[str, float]) -> float:
        """Calculate CPU/Memory optimization score (0-100)"""
        cpu_score = analysis['cpu_efficiency'] * 40
        memory_score = analysis['memory_efficiency'] * 40
        node_score = analysis['node_efficiency'] * 20
        
        return min(100, cpu_score + memory_score + node_score)
    
    def _calculate_storage_optimization_score(self, analysis: Dict[str, float]) -> float:
        """Calculate storage optimization score (0-100)"""
        ebs_score = analysis['ebs_efficiency'] * 40
        s3_score = analysis['s3_optimization_coverage'] * 35
        efs_score = analysis['efs_efficiency'] * 25
        
        return min(100, ebs_score + s3_score + efs_score)
    
    def _calculate_network_optimization_score(self, analysis: Dict[str, float]) -> float:
        """Calculate network optimization score (0-100)"""
        transfer_score = max(0, 100 - analysis['inter_az_cost_impact'] * 10) * 0.4
        lb_score = analysis['load_balancer_utilization'] * 100 * 0.6
        
        return min(100, transfer_score + lb_score)
    
    def _calculate_scheduling_optimization_score(self, analysis: Dict[str, float]) -> float:
        """Calculate scheduling optimization score (0-100)"""
        efficiency_score = analysis['scheduling_efficiency'] * 0.4
        contention_score = analysis['resource_contention_score'] * 0.3
        scaling_score = analysis['auto_scaling_efficiency'] * 0.3
        
        return min(100, efficiency_score + contention_score + scaling_score)
    
    def _prioritize_recommendations(self, recommendations: List[Dict]) -> List[Dict]:
        """Prioritize recommendations by impact and effort"""
        for rec in recommendations:
            # Assign priority based on potential savings and implementation effort
            if 'potential_savings' in rec:
                savings_str = rec['potential_savings']
                if '$' in savings_str:
                    # Extract numeric value
                    import re
                    numbers = re.findall(r'\d+\.?\d*', savings_str)
                    if numbers:
                        savings_value = float(numbers[0])
                        if savings_value > 100:
                            rec['priority'] = 'high'
                            rec['impact'] = 'high'
                        elif savings_value > 50:
                            rec['priority'] = 'medium'
                            rec['impact'] = 'medium'
                        else:
                            rec['priority'] = 'low'
                            rec['impact'] = 'low'
                elif '%' in savings_str:
                    # Extract percentage
                    import re
                    numbers = re.findall(r'\d+\.?\d*', savings_str)
                    if numbers:
                        savings_percent = float(numbers[0])
                        if savings_percent > 20:
                            rec['priority'] = 'high'
                            rec['impact'] = 'high'
                        elif savings_percent > 10:
                            rec['priority'] = 'medium'
                            rec['impact'] = 'medium'
                        else:
                            rec['priority'] = 'low'
                            rec['impact'] = 'low'
            
            # Assign effort based on recommendation type
            if rec.get('type') in ['cpu_rightsizing', 'memory_rightsizing', 's3_lifecycle_optimization']:
                rec['effort'] = 'low'
            elif rec.get('type') in ['workload_scheduling', 'auto_scaling_tuning']:
                rec['effort'] = 'medium'
            else:
                rec['effort'] = 'high'
        
        # Sort by priority and impact
        priority_order = {'high': 3, 'medium': 2, 'low': 1}
        return sorted(recommendations, 
                     key=lambda x: (priority_order.get(x.get('priority', 'low'), 1), 
                                   priority_order.get(x.get('impact', 'low'), 1)), 
                     reverse=True)
    
    def _calculate_total_potential_savings(self, recommendations: List[Dict]) -> Dict[str, float]:
        """Calculate total potential savings from recommendations"""
        monthly_savings = 0
        
        for rec in recommendations:
            if 'potential_savings' in rec:
                savings_str = rec['potential_savings']
                if '/month' in savings_str:
                    import re
                    numbers = re.findall(r'\d+\.?\d*', savings_str)
                    if numbers:
                        monthly_savings += float(numbers[0])
                elif '/day' in savings_str:
                    import re
                    numbers = re.findall(r'\d+\.?\d*', savings_str)
                    if numbers:
                        monthly_savings += float(numbers[0]) * 30
                elif '/hour' in savings_str:
                    import re
                    numbers = re.findall(r'\d+\.?\d*', savings_str)
                    if numbers:
                        monthly_savings += float(numbers[0]) * 24 * 30
        
        annual_savings = monthly_savings * 12
        roi_timeline_months = max(1, 6)  # Assume 6 months implementation time
        
        return {
            'monthly_savings': monthly_savings,
            'annual_savings': annual_savings,
            'roi_timeline_months': roi_timeline_months
        }
    
    def _generate_implementation_timeline(self, recommendations: List[Dict]) -> Dict[str, List[str]]:
        """Generate implementation timeline for recommendations"""
        timeline = {
            'immediate': [],  # 0-1 month
            'short_term': [],  # 1-3 months
            'medium_term': [],  # 3-6 months
            'long_term': []   # 6+ months
        }
        
        for rec in recommendations:
            effort = rec.get('effort', 'medium')
            priority = rec.get('priority', 'medium')
            
            if effort == 'low' and priority == 'high':
                timeline['immediate'].append(rec['description'])
            elif effort == 'low' or priority == 'high':
                timeline['short_term'].append(rec['description'])
            elif effort == 'medium':
                timeline['medium_term'].append(rec['description'])
            else:
                timeline['long_term'].append(rec['description'])
        
        return timeline
    
    def run_complete_analysis(self) -> Dict[str, Any]:
        """Run complete performance optimization analysis"""
        logger.info("🎯 Starting Performance Optimization Analysis")
        logger.info("=" * 80)
        
        start_time = datetime.now()
        
        try:
            # Run all analyses
            analyses = {
                'gpu_utilization': self.analyze_gpu_utilization_patterns(),
                'cpu_memory': self.analyze_cpu_memory_patterns(),
                'storage': self.analyze_storage_patterns(),
                'network': self.analyze_network_patterns(),
                'workload_scheduling': self.analyze_workload_scheduling_patterns()
            }
            
            # Generate optimization plan
            optimization_plan = self.generate_cost_optimization_plan(analyses)
            
            # Compile final report
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            report = {
                'execution_info': {
                    'start_time': start_time.isoformat(),
                    'end_time': end_time.isoformat(),
                    'duration_seconds': duration
                },
                'analyses': analyses,
                'optimization_plan': optimization_plan,
                'summary': {
                    'overall_optimization_score': optimization_plan['overall_optimization_score'],
                    'total_recommendations': optimization_plan['total_recommendations'],
                    'potential_monthly_savings': optimization_plan['potential_monthly_savings'],
                    'potential_annual_savings': optimization_plan['potential_annual_savings'],
                    'quick_wins_available': len(optimization_plan['quick_wins'])
                }
            }
            
            # Display summary
            logger.info("=" * 80)
            logger.info("🎉 Performance Optimization Analysis Complete!")
            logger.info("=" * 80)
            
            summary = report['summary']
            logger.info(f"⏱️  Analysis Duration: {duration:.1f} seconds")
            logger.info(f"🏆 Overall Optimization Score: {summary['overall_optimization_score']:.1f}/100")
            logger.info(f"📊 Total Recommendations: {summary['total_recommendations']}")
            logger.info(f"💰 Potential Monthly Savings: ${summary['potential_monthly_savings']:.2f}")
            logger.info(f"💰 Potential Annual Savings: ${summary['potential_annual_savings']:.2f}")
            logger.info(f"⚡ Quick Wins Available: {summary['quick_wins_available']}")
            
            logger.info("\n🔥 Top Quick Wins:")
            for i, quick_win in enumerate(optimization_plan['quick_wins'][:3], 1):
                logger.info(f"  {i}. {quick_win['description']}")
            
            # Save report
            report_file = f"tests/reports/performance_optimization_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            os.makedirs(os.path.dirname(report_file), exist_ok=True)
            
            with open(report_file, 'w') as f:
                json.dump(report, f, indent=2, default=str)
            
            logger.info(f"\n📄 Detailed report saved: {report_file}")
            
            return report
            
        except Exception as e:
            logger.error(f"❌ Performance optimization analysis failed: {e}")
            raise

def main():
    """Main analysis execution"""
    print("EMR to EKS Migration - Performance Optimization Analysis")
    print("=" * 80)
    print("This script analyzes actual usage patterns and provides")
    print("optimization recommendations for cost and performance.")
    print("=" * 80)
    print()
    
    import argparse
    parser = argparse.ArgumentParser(description='Performance Optimization Analysis')
    parser.add_argument('--region', default='us-west-2', help='AWS region')
    
    args = parser.parse_args()
    
    analyzer = PerformanceOptimizationAnalyzer(region=args.region)
    report = analyzer.run_complete_analysis()
    
    print("\n" + "=" * 80)
    print("Performance optimization analysis completed successfully!")
    print("Review the detailed report for comprehensive recommendations.")
    print("=" * 80)
    
    return report

if __name__ == "__main__":
    main()