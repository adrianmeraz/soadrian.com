# soadrian.com

The personal portfolio of Adrian Meraz: a buildless, responsive static site with an original retro-futurist visual system.

## Structure

```text
dist/                  Production-ready website
  assets/              Original generated editorial artwork
.openai/hosting.json   Sites deployment manifest
.github/workflows/     Repository checks
```

## Local preview

```powershell
python -m http.server 4173 --directory dist
```

Then open `http://localhost:4173`.

## Deployment

The production artifact is the `dist/` directory. ChatGPT Sites deploys the same committed source state that is mirrored to GitHub.

## Design notes

The design takes cues from the playful, high-energy composition of PartyRock while using an original type system, color palette, layouts, interactions, and custom-generated imagery.
