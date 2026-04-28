# Research Brief: AI Strategy for JEDI / JCSDA

**Date:** 2026-04-16
**Author:** Travis Sluka
**Purpose:** Build a strategic plan for incorporating AI into JEDI development, in
support of a proposed "Head of AI at JCSDA" role.

## Goal Statement (from user)

> I am looking to be promoted to a "Head of AI at JCSDA" position (position is yet to
> be created). I am looking to develop a strategic plan on how we can incorporate AI
> into our JEDI development plan. I am thinking we need to focus on 2 ends at the
> same time:
>
> 1. **Top-down:** The big foundational models (Silurian, Google, etc.), working with
>    them, leveraging their expertise, doing straight observation-to-forecast type of
>    stuff. Big things we can't necessarily do in-house, but we have a niche
>    specialty we can bring to the big AI dev groups.
>
> 2. **Bottom-up:** Using AI (torch) in our observation operators, or static B, our
>    models, other places that I can't even think of right now.

## Deliverable

A ~10-page internal strategy memo written for the **JCSDA director** as primary
audience (partner versions may be derived later). Purely technical — no org /
hiring / budget content. Heavy focus on **Year 1**, with a **3–5 year vision**
layered on top.

## Scope Decisions

| Dimension | Decision |
|---|---|
| Audience | JCSDA director (primary); derivative versions for partners later |
| Format | Internal strategy memo (Markdown → can be rendered to PDF later) |
| Length | ~10 pages |
| Horizon | FY27 heavy focus, FY28–FY31 vision |
| Headcount | Assume "small handful" of internal JCSDA people + partner collaboration |
| Budget | Aspirational — do not artificially constrain |
| Existing work | Unknown; scan the codebase (torch vertical balance, CRTM emulator rumored) |
| Named collaborators | NVIDIA has expressed interest. All others aspirational. |
| Peer positioning | ECMWF (AIFS, DestinE), NOAA EPIC, Navy/ONR, DeepMind, NVIDIA, Microsoft, Silurian, NASA |
| Component-level specificity | Yes — enumerate concrete bottom-up opportunities across JEDI |
| Differentiable JEDI | Explore as a stretch / enabling technology |
| Citations | Mixed — peer-reviewed, arXiv, ECMWF tech memos, vendor blogs all fair game |

## JCSDA / JEDI Niche (working hypothesis to test in memo)

- **JCSDA is a DA-first organization**, not a forecasting shop. Its comparative
  advantage against DeepMind, Google, NVIDIA, Microsoft, and Silurian is **not**
  training a bigger forecast model — it is **observation infrastructure, observation
  operators, and the DA algorithms that fuse observations with models**.
- Any top-down partnership posture should bring **observation expertise, error
  characterization, bias correction, and real-time observation handling** to the
  table, since the foundation-model shops generally do not have this depth.
- Bottom-up: the JEDI bundle has many well-bounded, high-value places where an ML
  component can be dropped in *without* replacing the DA algorithm — this is the
  lower-risk, higher-ROI path.

## Files in this folder

- `research_brief.md` — this file
- `existing_jedi_ai_work.md` — inventory of AI/ML already in the bundle
- `paper_foundation_weather_models.md` — distillations of GraphCast, GenCast, Pangu,
  FourCastNet, Aurora, AIFS, NeuralGCM
- `paper_ml_data_assimilation.md` — distillations of 4DVarNet, Aardvark, GraphDOP,
  score-based DA, differentiable DA, ML bias correction, learned obs operators
- `competitive_landscape.md` — ECMWF, NOAA EPIC, Navy, NASA, NVIDIA, Silurian,
  DeepMind, Microsoft
- `strategy_memo.md` — **final 10-page memo**

## Process notes

- Research papers are distilled into local markdown for quotable, citeable
  reference. Cite accurately — if a claim is from a blog post, mark it as such.
- No emojis in deliverables.
- This brief may be updated as assumptions are revised during research.
