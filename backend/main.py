import json,os
from fastapi import FastAPI,HTTPException
from pydantic import BaseModel,Field
from dotenv import load_dotenv
from openai import OpenAI
load_dotenv()
app=FastAPI(title="ExamMaster AI API",version="0.1.0")
class GenerateRequest(BaseModel):
    exam:str
    subject:str
    question_count:int=Field(default=10,ge=5,le=50)
    difficulty:str="Mixed"
@app.get("/health")
def health(): return {"status":"ok","service":"ExamMaster AI"}
@app.post("/v1/tests/generate")
def generate_test(req:GenerateRequest):
    key=os.getenv("OPENAI_API_KEY")
    if not key: raise HTTPException(500,"AI backend is not configured")
    client=OpenAI(api_key=key)
    prompt=f"""Create a fresh competitive-exam MCQ test.
Exam: {req.exam}
Subject: {req.subject}
Difficulty: {req.difficulty}
Questions: {req.question_count}
Return ONLY valid JSON with a questions array. Each item must contain question, options (exactly 4 strings), answer_index (0-3), and explanation.
Rules: exactly {req.question_count} questions; factually accurate for Indian competitive exams; no duplicates; no markdown."""
    try:
        response=client.chat.completions.create(
          model=os.getenv("OPENAI_MODEL","gpt-4o-mini"),temperature=0.7,
          response_format={"type":"json_object"},
          messages=[{"role":"system","content":"Generate accurate competitive-exam MCQs in strict JSON."},{"role":"user","content":prompt}])
        data=json.loads(response.choices[0].message.content)
        questions=data.get("questions",[])
        if len(questions)!=req.question_count: raise ValueError("Incorrect question count")
        return {"questions":questions}
    except Exception as exc:
        raise HTTPException(502,f"AI generation failed: {exc}")
