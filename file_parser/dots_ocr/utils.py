from enum import Enum, auto
import os
from PIL import Image


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


def detect_file_type(file_path):
    _, ext = os.path.splitext(file_path)
    ext = ext.lower
    for category, extensions in EXT_MAP.items():
        if ext in extensions:
            return category, ext
    return FileCategory.UNKNOWN, None


# def load_input(input_path):
#     file_type, ext = detect_file_type(input_path)
#     match file_type:
#         case FileCategory.TEXT:
#             pass
#         case FileCategory.IMAGE:
#             image = Image.open(input_path)
#             return FileCategory.IMAGE, image
#         case FileCategory.DOCUMENT:
#             pass