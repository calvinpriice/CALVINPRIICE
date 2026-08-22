# Vlog episodes — how to publish one

Everything lives on calvinpriice.com. No YouTube, no Vimeo, no video host,
no subscription. The tradeoff is size discipline — read the limits below.

## The two hard limits

1. **GitHub rejects any single file over 100 MB** (and warns at 50 MB).
   The site deploys from this repo, so an episode that's too big literally
   cannot be pushed.
2. **Netlify bills 20 credits per GB.** The free tier is 300 credits ≈ 15 GB
   per month. Every play of a 48 MB episode spends ~48 MB of that.

Practical result: **keep episodes at or under ~48 MB**, which is roughly
**7 minutes at 720p**. That leaves room for about 300 full plays a month.

If an episode needs to be longer, drop to `--height 540` or split it in two.

## Publishing an episode

```bash
# 1. compress + generate poster (+ captions if you have an SRT)
./tools/vlog-prep.sh ~/Desktop/raw-footage.MOV episode-01 --srt ~/Desktop/ep01.srt

# 2. copy the template and fill in the values the script prints
cp vlog/_template.html vlog/episode-01.html
#    ... replace every {{PLACEHOLDER}}, delete the noindex meta tag

# 3. add a card to vlog.html (commented example is at the top of the index)

# 4. add the URL to sitemap.xml

# 5. commit and push — Netlify deploys in ~20s
```

The script handles HDR footage from an iPhone automatically (it tone-maps
HLG/PQ down to SDR, otherwise the video looks grey and washed out), sets
`+faststart` so playback begins before the file finishes downloading, and
falls back to a two-pass encode if the first result busts the size ceiling.

Useful flags: `--height 540`, `--max-mb 40`, `--preset medium` (faster encode,
slightly bigger file), `--poster 00:01:12` (grab the thumbnail from elsewhere).

## Things not to change

- `preload="none"` on the `<video>` tag. This is why a visitor who never
  presses play costs you ~25 KB (the poster) instead of 48 MB.
- No `autoplay`. Autoplay would spend a full episode's bandwidth on every
  single pageview, including bots.
- One video per page. Never put multiple `<video>` elements on the index.

## If an episode takes off

If something goes viral you'll blow through the Netlify allowance. The fix is
one line per episode: change the `<source src="/videos/...">` to point at a
video host. The page, player, transcript, schema, and URL all stay identical —
nothing about this setup locks you in.

## Live streaming

Not possible on this setup, at any price. A livestream needs a server that
receives an RTMP feed and re-broadcasts it in real time; Netlify only serves
files that already exist. Live has to be Instagram, or a paid streaming service.
