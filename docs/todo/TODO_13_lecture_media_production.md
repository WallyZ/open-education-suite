# TODO 13 - Lecture Media Production

## Goal

Turn approved lecture packages into durable local media using a provider-neutral production pipeline that can route to the local `ComfyUI-automation` repo or approved cloud providers.

## Why This Matters

The platform can already plan, validate, and approve lecture packages. The next step is production: render voice, visuals, instructor/avatar presence, assembled media, checksums, archive metadata, and final publish approval without locking the suite to one vendor or losing local ownership of the artifacts.

## Tasks

- [x] Define production provider routing for local `ComfyUI-automation` and approved cloud providers without committing credentials. <!-- ms:id f89d97c83d7c -->
- [x] Add a deterministic dry-run production job builder for TTS, visuals, avatar, assembly, archive, and QA stages. <!-- ms:id 5a2bb34d9923 -->
- [x] Add a local ComfyUI adapter that can hand production jobs to the sibling `ComfyUI-automation` repo and read completed outputs. <!-- ms:id 26666ce3e0d1 -->
- [x] Add cloud provider adapter contracts for TTS, avatar, and video assembly with secret-free environment validation. <!-- ms:id 169442920c5e -->
- [x] Produce a real short lecture media file for the GDEV fixture and store it under the ignored lecture media archive. <!-- ms:id 4e05c2bd6e98 -->
- [x] Add checksum/archive manifest update tooling for rendered audio, video, captions, and package metadata. <!-- ms:id 6a1b686bd4a6 -->
- [x] Run the operator publish gate against a rendered package and record the publish-ready path. <!-- ms:id 5c5d207e366a -->
- [x] Add an end-to-end production smoke test that proves a rendered package can be selected and played from the learner flow. <!-- ms:id 7d6ed400071d -->

## Acceptance Notes

- Local ComfyUI production is the preferred first route when the repo is present and capable.
- Cloud providers are allowed only through explicit provider profiles and never through committed secrets.
- Required course media must be downloaded, archived, checksummed, and approved before publish.
- Host-only cloud outputs cannot satisfy required course paths.
