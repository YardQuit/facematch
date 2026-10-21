# Changelog

## 1.0.0

First release as a project of its own; before, it was the engine in the
facematch package of tuatara-packages.

Faces found by YuNet 2023mar, aligned with InsightFace's `norm_crop` and
compared by AuraFace-v1, each candidate given the probability that it shows
the person of the master photos, from the logistic curve fitted on LFW on
2026-10-11, with the ODNI's words for it. One AppImage, built from pinned
downloads: files by SHA-256, the models by commit, the Python packages by the
hashes in `requirements.txt`. `--version` is new.
