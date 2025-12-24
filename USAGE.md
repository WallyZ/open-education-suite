# Usage Guide

This guide explains how to use the tools, templates, and resources in the Open Education Suite.

---

## 1. Generating Flashcards

### PDF → Anki Pipeline
1. Place your PDF in `tools/pdf-to-anki/input/`
2. Run the flashcard generation script (see tool README)
3. Import the generated `.apkg` file into Anki

Use this for:
- Textbooks  
- Lecture notes  
- Research papers  

---

## 2. Creating a Study Plan

1. Copy the template from `study-plans/templates/study-plan-template.md`
2. Fill in:
   - Goals  
   - Resources  
   - Milestones  
   - Review schedule  
3. Save it under the appropriate discipline folder

---

## 3. Adding Resources

Place new resources under:
- `resources/textbooks/`  
- `resources/courses/`  
- `resources/youtube/`  
- `resources/practice-sites/`  

Each resource should include:
- Title  
- Link  
- Description  
- Recommended audience  

---

## 4. Running Automation Scripts

Scripts live under `scripts/` and may include:
- Setup helpers  
- Ingestion pipelines  
- Automation workflows  

Refer to each script’s README for usage details.
