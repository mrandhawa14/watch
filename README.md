# stream-share

A one-page video player your parents open in any phone/TV browser. They **stream** —
nothing downloads, no app, no file to share. Player is hosted free on GitHub Pages;
the video rides along as a GitHub Release asset (seek/scrub works via range requests).

## Publish a video
```bash
cd ~/stream-share
./add-video.sh /path/to/your-video.mp4
```
That uploads the file to a Release, points the player at it, and pushes.
It prints the link to send your parents:
`https://<you>.github.io/watch/`

## Notes
- **Format:** use **.mp4 (H.264 + AAC)** — it plays in every browser and on smart TVs.
  `.mkv` / HEVC / AV1 may not play on older devices.
- **Size limit:** GitHub Releases caps a file at **2 GB**. Bigger? Host the file on
  Cloudflare R2 (free 10 GB, free egress) and paste that URL into `config.js` as `videoUrl`.
- **Privacy:** a GitHub Pages site is public. For a little gating, set a `passphrase`
  in `config.js` (light obfuscation, not real security — the video URL is still public).
- **Change the title / add a passphrase:** edit `config.js`, then `git commit -am tweak && git push`.
- **Swap the video later:** just run `./add-video.sh` again with the new file.
