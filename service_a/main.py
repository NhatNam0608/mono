from fastapi import FastAPI
from utils import get_message  # Importing from the same directory
app = FastAPI()

@app.get("/")
def read_root():
    return {"message": get_message("message-from-service-a-adjusted-adjusted")}
