from fastapi import FastAPI
from utils import get_message  
app = FastAPI()

@app.get("/")
def read_root():
    return {"message": get_message("message-from-service-A-hong biet nói gì á")}
