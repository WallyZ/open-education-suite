# TODO 13 - Lecture Media Production

## Goal

Turn approved lecture packages into durable local media using a provider-neutral production pipeline that can route to the local `ComfyUI-automation` repo or approved cloud providers.

## Why This Matters

The platform can already plan, validate, and approve lecture packages. The next step is production: render voice, visuals, instructor/avatar presence, assembled media, checksums, archive metadata, and final publish approval without locking the suite to one vendor or losing local ownership of the artifacts.

## Tasks

- [x] Define production provider routing for local `ComfyUI-automation` and approved cloud providers without committing credentials.
- [x] Add a deterministic dry-run production job builder for TTS, visuals, avatar, assembly, archive, and QA stages.
- [x] Add a local ComfyUI adapter that can hand production jobs to the sibling `ComfyUI-automation` repo and read completed outputs.
- [x] Add cloud provider adapter contracts for TTS, avatar, and video assembly with secret-free environment validation.
- [x] Produce a real short lecture media file for the GDEV fixture and store it under the ignored lecture media archive.
- [x] Add checksum/archive manifest update tooling for rendered audio, video, captions, and package metadata.
- [x] Run the operator publish gate against a rendered package and record the publish-ready path.
- [x] Add an end-to-end production smoke test that proves a rendered package can be selected and played from the learner flow.

## Acceptance Notes

- Local ComfyUI production is the preferred first route when the repo is present and capable.
- Cloud providers are allowed only through explicit provider profiles and never through committed secrets.
- Required course media must be downloaded, archived, checksummed, and approved before publish.
- Host-only cloud outputs cannot satisfy required course paths.
