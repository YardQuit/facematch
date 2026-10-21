# facematch

A small program that finds the faces in master photos and candidate photos
and says, for each candidate, how probable it is that it shows the same
person: the probability, the ODNI's words for it (ICD 203, *Almost certain*
to *Almost no chance*) and the similarity behind it, the candidates ranked
most probable first.

It runs on its own from a terminal, and it is the engine of the facematch
package for the Tuatara editor, which chooses the photos in its file lists
and shows the ranking beside them.

| Step | What does it | Licence |
|---|---|---|
| Find the faces and their five landmarks | YuNet 2023mar (OpenCV Zoo) | MIT |
| Align each face | InsightFace's `norm_crop` | MIT (code) |
| Make it 512 numbers | AuraFace-v1's `glintr100.onnx` (fal), run by InsightFace's ArcFace runner on ONNX Runtime | Apache 2.0 |
| Similarity to probability | a logistic curve fitted on LFW (`calibration.json`) | — |

Only AuraFace's own model file is taken from its repository: the other files
there carry the names of InsightFace's research-only models.

## Getting it

Each release has `facematch-x86_64.AppImage`, one file with everything in it,
and `SHA256SUMS`. It runs on x86-64 Linux with glibc 2.39 or later, installs
nothing and never goes on the internet.

```sh
curl -LO https://github.com/YardQuit/facematch/releases/download/1.0.0/facematch-x86_64.AppImage
curl -LO https://github.com/YardQuit/facematch/releases/download/1.0.0/SHA256SUMS
sha256sum -c SHA256SUMS
chmod +x facematch-x86_64.AppImage
mkdir -p ~/Applications && mv facematch-x86_64.AppImage ~/Applications/
```

For Tuatara, name it in `~/.config/tuatara/init.lisp`; `M-x check-health`
says whether it is found:

```lisp
(load-package "facematch" :source "tuatara-packages"
  :config
  (setf *facematch-program* "~/Applications/facematch-x86_64.AppImage"))
```

Tuatara never downloads it: what runs is the file you checked.

## Running it

```sh
facematch-x86_64.AppImage --master a.jpg --master b.jpg --candidate c.jpg d.jpg [--json]
```

prints each candidate, the most probable first, with its probability (from
1% to 99%, the ends of the ODNI's scale), the words for it and its
similarity. A master's face is the largest in its photo; a candidate's is
whichever of its faces is likeliest. Several master photos are averaged into
one template, and how alike they are is printed first.

YuNet finds faces of moderate size, so a large photo (a camera's, a close-up
profile picture) is looked at made smaller, its longest side 640 pixels (then
1280 or 320 if that finds none); each face is then aligned and compared on the
photo itself, at full detail. LFW's photos are smaller than that, so the
calibration is untouched by it.

`--detection-confidence` (0.7 unless given) is how sure the detector must be
for a face to count; `--models` names another folder of the models and
`calibration.json`; `--version` says which facematch it is.

## Building it

```sh
./build-appimage.sh
```

makes `build/facematch-x86_64.AppImage` in an Ubuntu 24.04 podman container:
a relocatable Python (python-build-standalone 3.12), numpy 1.26, ONNX Runtime,
OpenCV and InsightFace 0.7.3 (its C parts compiled there against that numpy),
the two models with their licences, `facematch.py` and `calibration.json`.
Every download is pinned: files by their SHA-256, the models by the commit of
their repository too, and the Python packages by the hashes in
`requirements.txt`. Downloads are kept in `build/cache/`. The AppImage sets
`NO_ALBUMENTATIONS_UPDATE=1`, so that a library InsightFace loads never looks
for updates on the internet.

A release is made by pushing a version tag (`1.0.0`): the workflow builds the
AppImage from that tag, runs it, and publishes it with its `SHA256SUMS`.

## Calibrating

A similarity is not a probability. `calibrate.py` runs the same pipeline over
LFW's standard protocol (`pairs.txt`: ten folds of 300 same-person and 300
different-person pairs), fits a logistic curve P(same | similarity) on nine
folds and scores it on the tenth, ten times, then writes the curve fitted on
all pairs to `calibration.json` with the held-out scores and how the
probabilities hold in bands.

```sh
./build-appimage.sh --env          # the container's Python, with the models
# LFW's photos (lfw.tgz) and pairs.txt, unpacked somewhere, copied into the container, then:
python3 calibrate.py --lfw lfw --pairs pairs.txt --models models --out calibration.json
```

The pairs are half the same person, so the probabilities are at **even prior
odds**: they say how the photos change the odds, starting from 50%. LFW is
news photography, mostly frontal and well lit; photos met in practice vary
more.

The calibration of 2026-10-11 on LFW: 98.8% of pairs right at 50% on folds
the curve never saw (±0.3%), Brier score 0.010; see `calibration.json` for the
bands.

## Licence

GPL-3.0-or-later; see `LICENSE`. The models keep their own licences, which
the AppImage carries in `usr/share/facematch/licenses/`.
