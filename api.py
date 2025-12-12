import os
import uuid
import io
import sys

from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware

from model import predict_word, DEFAULT_MODEL_PATH, DEFAULT_LABELS_PATH

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,  
    allow_methods=["*"],
    allow_headers=["*"],
)


UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.get("/health")
def health():
    return {"ok": True}

@app.post("/predict-word")
async def predict_word_api(
    image: UploadFile = File(...),
    infer_orientation: str = "none",
):
    ext = os.path.splitext(image.filename)[1].lower() or ".jpg"
    filename = f"{uuid.uuid4().hex}{ext}"
    path = os.path.join(UPLOAD_DIR, filename)

    data = await image.read()
    with open(path, "wb") as f:
        f.write(data)

    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        predict_word(
            image_path=path,
            model_path=DEFAULT_MODEL_PATH,
            labels_path=DEFAULT_LABELS_PATH,
            infer_orientation=infer_orientation,
            dump_chars=False,
            debug_boxes=True,
        )
        result_text = sys.stdout.getvalue().strip()
    finally:
        sys.stdout = old

    return {"prediction": result_text}
