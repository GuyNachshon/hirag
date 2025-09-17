import logging
import sys
from datetime import datetime
from pathlib import Path
from logging.handlers import RotatingFileHandler
import json
import traceback
from typing import Dict, Any, Optional

class APILogger:
    """Centralized logging configuration for the offline RAG API"""
    
    def __init__(self, log_dir: str = "logs", log_level: str = "INFO"):
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(exist_ok=True)
        self.log_level = getattr(logging, log_level.upper())
        
        # Create formatters
        self.detailed_formatter = logging.Formatter(
            '%(asctime)s | %(name)s | %(levelname)s | %(funcName)s:%(lineno)d | %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        self.json_formatter = JSONFormatter()
        
        # Setup loggers
        self._setup_main_logger()
        self._setup_access_logger()
        self._setup_error_logger()
        self._setup_performance_logger()
        self._setup_rag_logger()
    
    def _setup_main_logger(self):
        """Setup main application logger"""
        self.main_logger = logging.getLogger("rag_api")
        self.main_logger.setLevel(self.log_level)
        
        # File handler
        file_handler = RotatingFileHandler(
            self.log_dir / "api_main.log",
            maxBytes=10*1024*1024,  # 10MB
            backupCount=5
        )
        file_handler.setFormatter(self.detailed_formatter)
        file_handler.setLevel(self.log_level)
        
        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(self.detailed_formatter)
        console_handler.setLevel(logging.INFO)
        
        self.main_logger.addHandler(file_handler)
        self.main_logger.addHandler(console_handler)
    
    def _setup_access_logger(self):
        """Setup API access logger"""
        self.access_logger = logging.getLogger("rag_api.access")
        self.access_logger.setLevel(logging.INFO)
        
        file_handler = RotatingFileHandler(
            self.log_dir / "api_access.log",
            maxBytes=50*1024*1024,  # 50MB
            backupCount=10
        )
        file_handler.setFormatter(self.json_formatter)
        
        self.access_logger.addHandler(file_handler)
        self.access_logger.propagate = False
    
    def _setup_error_logger(self):
        """Setup error logger"""
        self.error_logger = logging.getLogger("rag_api.errors")
        self.error_logger.setLevel(logging.ERROR)
        
        file_handler = RotatingFileHandler(
            self.log_dir / "api_errors.log",
            maxBytes=20*1024*1024,  # 20MB
            backupCount=5
        )
        file_handler.setFormatter(self.detailed_formatter)
        
        self.error_logger.addHandler(file_handler)
        self.error_logger.propagate = False
    
    def _setup_performance_logger(self):
        """Setup performance monitoring logger"""
        self.performance_logger = logging.getLogger("rag_api.performance")
        self.performance_logger.setLevel(logging.INFO)
        
        file_handler = RotatingFileHandler(
            self.log_dir / "api_performance.log",
            maxBytes=30*1024*1024,  # 30MB
            backupCount=5
        )
        file_handler.setFormatter(self.json_formatter)
        
        self.performance_logger.addHandler(file_handler)
        self.performance_logger.propagate = False
    
    def _setup_rag_logger(self):
        """Setup RAG-specific operations logger"""
        self.rag_logger = logging.getLogger("rag_api.rag_ops")
        self.rag_logger.setLevel(logging.INFO)
        
        file_handler = RotatingFileHandler(
            self.log_dir / "rag_operations.log",
            maxBytes=40*1024*1024,  # 40MB
            backupCount=5
        )
        file_handler.setFormatter(self.json_formatter)
        
        self.rag_logger.addHandler(file_handler)
        self.rag_logger.propagate = False
    
    def log_api_access(self, request_data: Dict[str, Any]):
        """Log API access"""
        self.access_logger.info("api_access", extra={"data": request_data})
    
    def log_error(self, error: Exception, context: Optional[Dict[str, Any]] = None):
        """Log error with full traceback"""
        error_data = {
            "error_type": type(error).__name__,
            "error_message": str(error),
            "traceback": traceback.format_exc(),
            "context": context or {}
        }
        self.error_logger.error("error_occurred", extra={"data": error_data})
    
    def log_performance(self, operation: str, duration: float, metadata: Optional[Dict[str, Any]] = None):
        """Log performance metrics"""
        perf_data = {
            "operation": operation,
            "duration_seconds": round(duration, 4),
            "metadata": metadata or {}
        }
        self.performance_logger.info("performance_metric", extra={"data": perf_data})
    
    def log_rag_operation(self, operation: str, details: Dict[str, Any]):
        """Log RAG-specific operations"""
        rag_data = {
            "operation": operation,
            "timestamp": datetime.now().isoformat(),
            **details
        }
        self.rag_logger.info("rag_operation", extra={"data": rag_data})

class JSONFormatter(logging.Formatter):
    """Custom JSON formatter for structured logging"""
    
    def format(self, record):
        log_entry = {
            "timestamp": datetime.fromtimestamp(record.created).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
            "message": record.getMessage(),
        }
        
        # Add extra data if present
        if hasattr(record, 'data'):
            log_entry["data"] = record.data
        
        return json.dumps(log_entry, ensure_ascii=False)

# Global logger instance
api_logger = None

def setup_logging(log_dir: str = "logs", log_level: str = "INFO"):
    """Setup logging for the application"""
    global api_logger
    api_logger = APILogger(log_dir, log_level)
    return api_logger

def get_logger():
    """Get the global logger instance"""
    global api_logger
    if api_logger is None:
        api_logger = setup_logging()
    return api_logger