#!/usr/bin/env python3
"""
Training Job Monitoring and Logging for Ray XGBoost
Implements comprehensive monitoring and logging functionality for distributed training

Requirements implemented:
- 2.4: Training job monitoring and logging functionality
- Real-time metrics collection and reporting
- CloudWatch integration for centralized logging
- Performance tracking and alerting
"""

import os
import time
import json
import logging
import threading
from typing import Dict, List, Any, Optional, Callable
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
import traceback

import boto3
import psutil
import ray
from ray.util.metrics import Counter, Histogram, Gauge
import numpy as np

# Configure logging
logger = logging.getLogger(__name__)

@dataclass
class TrainingMetrics:
    """Data class for training metrics"""
    timestamp: datetime
    epoch: int
    train_loss: float
    train_auc: float
    valid_loss: Optional[float] = None
    valid_auc: Optional[float] = None
    learning_rate: Optional[float] = None
    training_time: Optional[float] = None
    memory_usage_mb: Optional[float] = None
    gpu_utilization: Optional[float] = None
    cpu_utilization: Optional[float] = None

@dataclass
class SystemMetrics:
    """Data class for system metrics"""
    timestamp: datetime
    cpu_percent: float
    memory_percent: float
    memory_used_gb: float
    memory_available_gb: float
    disk_usage_percent: float
    gpu_memory_used_mb: Optional[float] = None
    gpu_memory_total_mb: Optional[float] = None
    gpu_utilization_percent: Optional[float] = None
    network_io_mb: Optional[float] = None

class CloudWatchLogger:
    """CloudWatch integration for centralized logging"""
    
    def __init__(self, log_group: str, log_stream: str, region: str = 'us-west-2'):
        """
        Initialize CloudWatch logger
        
        Args:
            log_group: CloudWatch log group name
            log_stream: CloudWatch log stream name
            region: AWS region
        """
        self.log_group = log_group
        self.log_stream = log_stream
        self.region = region
        
        try:
            self.cloudwatch_logs = boto3.client('logs', region_name=region)
            self._ensure_log_group_exists()
            self._ensure_log_stream_exists()
            logger.info(f"CloudWatch logger initialized: {log_group}/{log_stream}")
        except Exception as e:
            logger.warning(f"Failed to initialize CloudWatch logger: {str(e)}")
            self.cloudwatch_logs = None
    
    def _ensure_log_group_exists(self):
        """Ensure log group exists"""
        try:
            self.cloudwatch_logs.create_log_group(logGroupName=self.log_group)
        except self.cloudwatch_logs.exceptions.ResourceAlreadyExistsException:
            pass
    
    def _ensure_log_stream_exists(self):
        """Ensure log stream exists"""
        try:
            self.cloudwatch_logs.create_log_stream(
                logGroupName=self.log_group,
                logStreamName=self.log_stream
            )
        except self.cloudwatch_logs.exceptions.ResourceAlreadyExistsException:
            pass
    
    def log_metrics(self, metrics: Dict[str, Any]):
        """
        Log metrics to CloudWatch
        
        Args:
            metrics: Dictionary of metrics to log
        """
        if not self.cloudwatch_logs:
            return
        
        try:
            log_event = {
                'timestamp': int(time.time() * 1000),
                'message': json.dumps(metrics, default=str)
            }
            
            self.cloudwatch_logs.put_log_events(
                logGroupName=self.log_group,
                logStreamName=self.log_stream,
                logEvents=[log_event]
            )
        except Exception as e:
            logger.warning(f"Failed to log to CloudWatch: {str(e)}")

class GPUMonitor:
    """GPU monitoring utilities"""
    
    def __init__(self):
        """Initialize GPU monitor"""
        self.gpu_available = False
        try:
            import pynvml
            pynvml.nvmlInit()
            self.gpu_count = pynvml.nvmlDeviceGetCount()
            self.gpu_available = self.gpu_count > 0
            self.pynvml = pynvml
            logger.info(f"GPU monitoring initialized: {self.gpu_count} GPUs available")
        except ImportError:
            logger.warning("pynvml not available, GPU monitoring disabled")
        except Exception as e:
            logger.warning(f"Failed to initialize GPU monitoring: {str(e)}")
    
    def get_gpu_metrics(self) -> Optional[Dict[str, float]]:
        """
        Get GPU metrics
        
        Returns:
            Dictionary of GPU metrics or None if not available
        """
        if not self.gpu_available:
            return None
        
        try:
            handle = self.pynvml.nvmlDeviceGetHandleByIndex(0)  # First GPU
            
            # Memory info
            mem_info = self.pynvml.nvmlDeviceGetMemoryInfo(handle)
            memory_used_mb = mem_info.used / 1024 / 1024
            memory_total_mb = mem_info.total / 1024 / 1024
            
            # Utilization
            util = self.pynvml.nvmlDeviceGetUtilizationRates(handle)
            gpu_utilization = util.gpu
            
            return {
                'gpu_memory_used_mb': memory_used_mb,
                'gpu_memory_total_mb': memory_total_mb,
                'gpu_utilization_percent': gpu_utilization,
                'gpu_memory_percent': (memory_used_mb / memory_total_mb) * 100
            }
        except Exception as e:
            logger.warning(f"Failed to get GPU metrics: {str(e)}")
            return None

class TrainingMonitor:
    """
    Comprehensive training monitor for Ray XGBoost training
    Provides real-time monitoring, logging, and alerting capabilities
    """
    
    def __init__(self, config: Dict[str, Any]):
        """
        Initialize training monitor
        
        Args:
            config: Monitoring configuration
        """
        self.config = config
        self.start_time = datetime.now()
        self.training_metrics_history: List[TrainingMetrics] = []
        self.system_metrics_history: List[SystemMetrics] = []
        
        # Initialize components
        self.gpu_monitor = GPUMonitor()
        
        # CloudWatch logger
        if config.get('enable_cloudwatch', True):
            log_group = config.get('cloudwatch_log_group', '/aws/eks/ray-training')
            log_stream = f"training-{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            self.cloudwatch_logger = CloudWatchLogger(log_group, log_stream)
        else:
            self.cloudwatch_logger = None
        
        # Ray metrics
        self._setup_ray_metrics()
        
        # Monitoring thread
        self.monitoring_active = False
        self.monitoring_thread = None
        
        # Alert thresholds
        self.alert_thresholds = {
            'memory_usage_percent': config.get('memory_alert_threshold', 90),
            'gpu_memory_percent': config.get('gpu_memory_alert_threshold', 95),
            'training_stall_minutes': config.get('training_stall_alert_minutes', 30),
            'min_auc_improvement': config.get('min_auc_improvement', 0.001)
        }
        
        logger.info("Training monitor initialized")
    
    def _setup_ray_metrics(self):
        """Setup Ray metrics collectors"""
        try:
            self.ray_metrics = {
                'training_loss': Gauge('training_loss', description='Training loss'),
                'training_auc': Gauge('training_auc', description='Training AUC'),
                'validation_auc': Gauge('validation_auc', description='Validation AUC'),
                'memory_usage': Gauge('memory_usage_mb', description='Memory usage in MB'),
                'gpu_utilization': Gauge('gpu_utilization', description='GPU utilization %'),
                'training_time': Histogram('training_time_seconds', description='Training time per epoch')
            }
            logger.info("Ray metrics setup completed")
        except Exception as e:
            logger.warning(f"Failed to setup Ray metrics: {str(e)}")
            self.ray_metrics = {}
    
    def start_monitoring(self, interval_seconds: int = 30):
        """
        Start background monitoring
        
        Args:
            interval_seconds: Monitoring interval in seconds
        """
        if self.monitoring_active:
            logger.warning("Monitoring already active")
            return
        
        self.monitoring_active = True
        self.monitoring_thread = threading.Thread(
            target=self._monitoring_loop,
            args=(interval_seconds,),
            daemon=True
        )
        self.monitoring_thread.start()
        logger.info(f"Background monitoring started with {interval_seconds}s interval")
    
    def stop_monitoring(self):
        """Stop background monitoring"""
        self.monitoring_active = False
        if self.monitoring_thread:
            self.monitoring_thread.join(timeout=5)
        logger.info("Background monitoring stopped")
    
    def _monitoring_loop(self, interval_seconds: int):
        """Background monitoring loop"""
        while self.monitoring_active:
            try:
                self._collect_system_metrics()
                self._check_alerts()
                time.sleep(interval_seconds)
            except Exception as e:
                logger.error(f"Error in monitoring loop: {str(e)}")
                time.sleep(interval_seconds)
    
    def _collect_system_metrics(self):
        """Collect system metrics"""
        try:
            # CPU and memory
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            # Network I/O
            network = psutil.net_io_counters()
            network_io_mb = (network.bytes_sent + network.bytes_recv) / 1024 / 1024
            
            # GPU metrics
            gpu_metrics = self.gpu_monitor.get_gpu_metrics()
            
            # Create system metrics
            system_metrics = SystemMetrics(
                timestamp=datetime.now(),
                cpu_percent=cpu_percent,
                memory_percent=memory.percent,
                memory_used_gb=memory.used / 1024 / 1024 / 1024,
                memory_available_gb=memory.available / 1024 / 1024 / 1024,
                disk_usage_percent=disk.percent,
                network_io_mb=network_io_mb
            )
            
            if gpu_metrics:
                system_metrics.gpu_memory_used_mb = gpu_metrics['gpu_memory_used_mb']
                system_metrics.gpu_memory_total_mb = gpu_metrics['gpu_memory_total_mb']
                system_metrics.gpu_utilization_percent = gpu_metrics['gpu_utilization_percent']
            
            # Store metrics
            self.system_metrics_history.append(system_metrics)
            
            # Update Ray metrics
            if 'memory_usage' in self.ray_metrics:
                self.ray_metrics['memory_usage'].set(system_metrics.memory_used_gb * 1024)
            
            if gpu_metrics and 'gpu_utilization' in self.ray_metrics:
                self.ray_metrics['gpu_utilization'].set(gpu_metrics['gpu_utilization_percent'])
            
            # Log to CloudWatch
            if self.cloudwatch_logger:
                self.cloudwatch_logger.log_metrics({
                    'type': 'system_metrics',
                    'metrics': asdict(system_metrics)
                })
            
        except Exception as e:
            logger.error(f"Error collecting system metrics: {str(e)}")
    
    def log_training_metrics(self, epoch: int, train_loss: float, train_auc: float,
                           valid_loss: Optional[float] = None, valid_auc: Optional[float] = None,
                           learning_rate: Optional[float] = None, training_time: Optional[float] = None):
        """
        Log training metrics
        
        Args:
            epoch: Training epoch
            train_loss: Training loss
            train_auc: Training AUC
            valid_loss: Validation loss (optional)
            valid_auc: Validation AUC (optional)
            learning_rate: Current learning rate (optional)
            training_time: Training time for this epoch (optional)
        """
        try:
            # Get current system metrics
            memory = psutil.virtual_memory()
            gpu_metrics = self.gpu_monitor.get_gpu_metrics()
            
            # Create training metrics
            training_metrics = TrainingMetrics(
                timestamp=datetime.now(),
                epoch=epoch,
                train_loss=train_loss,
                train_auc=train_auc,
                valid_loss=valid_loss,
                valid_auc=valid_auc,
                learning_rate=learning_rate,
                training_time=training_time,
                memory_usage_mb=memory.used / 1024 / 1024,
                cpu_utilization=psutil.cpu_percent(),
                gpu_utilization=gpu_metrics['gpu_utilization_percent'] if gpu_metrics else None
            )
            
            # Store metrics
            self.training_metrics_history.append(training_metrics)
            
            # Update Ray metrics
            if 'training_loss' in self.ray_metrics:
                self.ray_metrics['training_loss'].set(train_loss)
            if 'training_auc' in self.ray_metrics:
                self.ray_metrics['training_auc'].set(train_auc)
            if valid_auc and 'validation_auc' in self.ray_metrics:
                self.ray_metrics['validation_auc'].set(valid_auc)
            if training_time and 'training_time' in self.ray_metrics:
                self.ray_metrics['training_time'].observe(training_time)
            
            # Log to CloudWatch
            if self.cloudwatch_logger:
                self.cloudwatch_logger.log_metrics({
                    'type': 'training_metrics',
                    'metrics': asdict(training_metrics)
                })
            
            # Console logging
            logger.info(f"Epoch {epoch}: train_loss={train_loss:.4f}, train_auc={train_auc:.4f}")
            if valid_auc:
                logger.info(f"Epoch {epoch}: valid_loss={valid_loss:.4f}, valid_auc={valid_auc:.4f}")
            
        except Exception as e:
            logger.error(f"Error logging training metrics: {str(e)}")
    
    def _check_alerts(self):
        """Check for alert conditions"""
        try:
            current_time = datetime.now()
            
            # Check system metrics
            if self.system_metrics_history:
                latest_system = self.system_metrics_history[-1]
                
                # Memory alert
                if latest_system.memory_percent > self.alert_thresholds['memory_usage_percent']:
                    self._send_alert(
                        'HIGH_MEMORY_USAGE',
                        f"Memory usage: {latest_system.memory_percent:.1f}%"
                    )
                
                # GPU memory alert
                if (latest_system.gpu_memory_used_mb and latest_system.gpu_memory_total_mb):
                    gpu_percent = (latest_system.gpu_memory_used_mb / latest_system.gpu_memory_total_mb) * 100
                    if gpu_percent > self.alert_thresholds['gpu_memory_percent']:
                        self._send_alert(
                            'HIGH_GPU_MEMORY_USAGE',
                            f"GPU memory usage: {gpu_percent:.1f}%"
                        )
            
            # Check training progress
            if len(self.training_metrics_history) > 1:
                latest_training = self.training_metrics_history[-1]
                time_since_last = current_time - latest_training.timestamp
                
                # Training stall alert
                stall_threshold = timedelta(minutes=self.alert_thresholds['training_stall_minutes'])
                if time_since_last > stall_threshold:
                    self._send_alert(
                        'TRAINING_STALLED',
                        f"No training progress for {time_since_last.total_seconds()/60:.1f} minutes"
                    )
                
                # AUC improvement alert
                if len(self.training_metrics_history) >= 10:
                    recent_aucs = [m.train_auc for m in self.training_metrics_history[-10:]]
                    auc_improvement = max(recent_aucs) - min(recent_aucs)
                    if auc_improvement < self.alert_thresholds['min_auc_improvement']:
                        self._send_alert(
                            'LOW_AUC_IMPROVEMENT',
                            f"AUC improvement in last 10 epochs: {auc_improvement:.4f}"
                        )
            
        except Exception as e:
            logger.error(f"Error checking alerts: {str(e)}")
    
    def _send_alert(self, alert_type: str, message: str):
        """
        Send alert notification
        
        Args:
            alert_type: Type of alert
            message: Alert message
        """
        alert_data = {
            'type': 'alert',
            'alert_type': alert_type,
            'message': message,
            'timestamp': datetime.now().isoformat(),
            'training_duration_minutes': (datetime.now() - self.start_time).total_seconds() / 60
        }
        
        logger.warning(f"ALERT [{alert_type}]: {message}")
        
        # Log to CloudWatch
        if self.cloudwatch_logger:
            self.cloudwatch_logger.log_metrics(alert_data)
        
        # Could add SNS notification here
        # self._send_sns_alert(alert_data)
    
    def get_training_summary(self) -> Dict[str, Any]:
        """
        Get training summary statistics
        
        Returns:
            Dictionary with training summary
        """
        if not self.training_metrics_history:
            return {'error': 'No training metrics available'}
        
        try:
            # Training metrics summary
            train_aucs = [m.train_auc for m in self.training_metrics_history]
            valid_aucs = [m.valid_auc for m in self.training_metrics_history if m.valid_auc]
            training_times = [m.training_time for m in self.training_metrics_history if m.training_time]
            
            summary = {
                'training_duration_minutes': (datetime.now() - self.start_time).total_seconds() / 60,
                'total_epochs': len(self.training_metrics_history),
                'best_train_auc': max(train_aucs) if train_aucs else None,
                'latest_train_auc': train_aucs[-1] if train_aucs else None,
                'best_valid_auc': max(valid_aucs) if valid_aucs else None,
                'latest_valid_auc': valid_aucs[-1] if valid_aucs else None,
                'avg_epoch_time_seconds': np.mean(training_times) if training_times else None,
                'total_training_time_seconds': sum(training_times) if training_times else None
            }
            
            # System metrics summary
            if self.system_metrics_history:
                memory_usage = [m.memory_percent for m in self.system_metrics_history]
                cpu_usage = [m.cpu_percent for m in self.system_metrics_history]
                gpu_usage = [m.gpu_utilization_percent for m in self.system_metrics_history 
                           if m.gpu_utilization_percent]
                
                summary.update({
                    'avg_memory_usage_percent': np.mean(memory_usage),
                    'max_memory_usage_percent': max(memory_usage),
                    'avg_cpu_usage_percent': np.mean(cpu_usage),
                    'max_cpu_usage_percent': max(cpu_usage),
                    'avg_gpu_usage_percent': np.mean(gpu_usage) if gpu_usage else None,
                    'max_gpu_usage_percent': max(gpu_usage) if gpu_usage else None
                })
            
            return summary
            
        except Exception as e:
            logger.error(f"Error generating training summary: {str(e)}")
            return {'error': str(e)}
    
    def save_metrics_to_s3(self, s3_bucket: str, s3_prefix: str) -> str:
        """
        Save all collected metrics to S3
        
        Args:
            s3_bucket: S3 bucket name
            s3_prefix: S3 prefix for metrics
            
        Returns:
            S3 path where metrics were saved
        """
        try:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            
            # Prepare metrics data
            metrics_data = {
                'training_summary': self.get_training_summary(),
                'training_metrics': [asdict(m) for m in self.training_metrics_history],
                'system_metrics': [asdict(m) for m in self.system_metrics_history],
                'config': self.config,
                'start_time': self.start_time.isoformat(),
                'end_time': datetime.now().isoformat()
            }
            
            # Save to local file first
            local_path = f"/tmp/training_metrics_{timestamp}.json"
            with open(local_path, 'w') as f:
                json.dump(metrics_data, f, indent=2, default=str)
            
            # Upload to S3
            s3_client = boto3.client('s3')
            s3_key = f"{s3_prefix}/training_metrics_{timestamp}.json"
            s3_client.upload_file(local_path, s3_bucket, s3_key)
            
            s3_path = f"s3://{s3_bucket}/{s3_key}"
            logger.info(f"Training metrics saved to: {s3_path}")
            
            # Cleanup local file
            os.remove(local_path)
            
            return s3_path
            
        except Exception as e:
            logger.error(f"Error saving metrics to S3: {str(e)}")
            raise

class TrainingCallback:
    """
    Callback for XGBoost training to integrate with monitoring
    """
    
    def __init__(self, monitor: TrainingMonitor):
        """
        Initialize callback
        
        Args:
            monitor: Training monitor instance
        """
        self.monitor = monitor
        self.epoch_start_time = None
    
    def before_iteration(self, model, epoch, evals_log):
        """Called before each training iteration"""
        self.epoch_start_time = time.time()
    
    def after_iteration(self, model, epoch, evals_log):
        """Called after each training iteration"""
        try:
            if self.epoch_start_time:
                training_time = time.time() - self.epoch_start_time
            else:
                training_time = None
            
            # Extract metrics from evals_log
            train_loss = None
            train_auc = None
            valid_loss = None
            valid_auc = None
            
            if 'train' in evals_log:
                if 'logloss' in evals_log['train']:
                    train_loss = evals_log['train']['logloss'][-1]
                if 'auc' in evals_log['train']:
                    train_auc = evals_log['train']['auc'][-1]
            
            if 'valid' in evals_log:
                if 'logloss' in evals_log['valid']:
                    valid_loss = evals_log['valid']['logloss'][-1]
                if 'auc' in evals_log['valid']:
                    valid_auc = evals_log['valid']['auc'][-1]
            
            # Log metrics
            if train_loss and train_auc:
                self.monitor.log_training_metrics(
                    epoch=epoch,
                    train_loss=train_loss,
                    train_auc=train_auc,
                    valid_loss=valid_loss,
                    valid_auc=valid_auc,
                    training_time=training_time
                )
            
        except Exception as e:
            logger.error(f"Error in training callback: {str(e)}")


def create_training_monitor(config: Dict[str, Any]) -> TrainingMonitor:
    """
    Factory function to create training monitor
    
    Args:
        config: Monitor configuration
        
    Returns:
        TrainingMonitor instance
    """
    return TrainingMonitor(config)