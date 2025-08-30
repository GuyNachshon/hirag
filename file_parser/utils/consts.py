from enum import Enum, auto

MIN_PIXELS=3136
MAX_PIXELS=11289600
IMAGE_FACTOR=28

class FileCategory(Enum):
    TEXT = auto()
    IMAGE = auto()
    DOCUMENT = auto()
    SPREADSHEET = auto()
    PRESENTATION = auto()
    ZIP = auto()
    UNKNOWN = auto()


EXT_MAP = {
    FileCategory.TEXT: {".txt", ".md", ".rtf"},
    FileCategory.IMAGE: {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp"},
    FileCategory.DOCUMENT: {".doc", ".docx", ".pdf", ".odt"},
    FileCategory.SPREADSHEET: {".xls", ".xlsx", ".ods", ".csv"},
    FileCategory.PRESENTATION: {".ppt", ".pptx", ".odp"},
    FileCategory.ZIP: {".zip", ".gzip", ".tar", ".tar.gz", ".gz", ".7zip"}
}