# For Rubyists: the 25-minute code tour

A narrative of the workshop for people who already know Rails and want to see what changes when the Rails 8 monolith moves to a cloud platform. It was written for Helvetic Ruby 2026 (Zurich, 19 Nov 2026) and works for any Ruby audience.

- Deck, ready to present: <https://palladius.github.io/rails8-app-on-gcp/slides/rubyists.en.html> (18 slides; press `P` for the speaker notes)
- Deck source: [`slides/rubyists.en.md`](../../../slides/rubyists.en.md) (Marp Markdown, built to `slides/dist/rubyists.en.html`)
- Event page: [`workshop/events/20261119-helvetic-ruby/README.md`](../../events/20261119-helvetic-ruby/README.md)
- Codelab: [`workshop/CODELAB.md`](../../CODELAB.md)

The order of the message is fixed: first, this app is a solid blueprint for running Rails 8 in the cloud; second, the codelab is fun; third, you practise working with a coding harness, whichever one you use.

All `file:line` references below were checked against the tree at the commit that added this file. If a file changes, fix the reference here and in the speaker notes of the deck.

---

## Part 1: Presenter runbook

### Before the room fills

1. Serve the deck from the repository root: `just slides`, then open `http://localhost:8082/rubyists.en.md`. Press `P` for the presenter view with speaker notes. Use this (or the published page) rather than opening `slides/dist/rubyists.en.html` from disk: the deck loads its images from `images/`, which sits next to the Markdown source, not next to the local build.
2. Open the repository in an editor with line numbers, in a second window. The tour is more convincing in the real files than on slides.
3. Open the codelab in a browser tab: <https://palladius.github.io/rails8-app-on-gcp/codelab/>.
4. Have one deployed instance of the app ready in another tab if you can. If you cannot, say so and stay in the code.

### Timeline

| Minute | Slide | Stop | What to open |
|---|---|---|---|
| 0 to 1 | 1 | Welcome | the cover; its small link plays the workshop anthem, its QR code opens the published deck |
| 1 to 2 | 2 | What you need today | the four links: slides, repository, codelab, credits |
| 2 to 3 | 3 | Oh no, yet another blog app | the deployed app, if you have one |
| 3 to 5 | 4 | Now look behind it | `.env.dist:42` (`IAP_ALLOWED_USERS`) |
| 5 to 6 | 5 | What a clean container breaks | `blog/config/puma.rb:38` |
| 6 to 9 | 6 | One-line JSON logs | `blog/config/environments/production.rb:44`, `blog/lib/google_json_formatter.rb:19` |
| 9 to 12 | 7 | Solid Queue, Cache, Cable; three containers | `blog/config/environments/production.rb:64`, `blog/compose.prod.yaml:7` |
| 12 to 15 | 8 | Private Active Storage, keyless signed URLs | `blog/config/storage.yml:63` |
| 15 to 19 | 9 | Database through a sidecar, secrets at runtime | `blog/config/database.yml:44`, `blog/compose.prod.yaml:21` |
| 19 to 23 | 10 | AI as a background job, no API key | `blog/app/jobs/generate_cover_image_job.rb:9`, `blog/lib/nanobanana.rb:97` |
| 23 to 25 | 11 | The same blueprint elsewhere | `docs/CONSTITUTION.md`, section 13 |
| 25 to 30 | 12 to 16 | Hands-on kickoff: harness, codelab, guardrails, route, questions | the codelab |
| Wrap-up | 17 | Thank you | the last section of the codelab, "Conclusion & Clean Up" |
| After the end | 18 | Bonus: the triumvirs of RubyCon Italy | nothing; show it only if there is time |

### What to say at each stop

**Welcome (slide 1).** Emiliano Della Casa and Riccardo run RubyCon Italy and built this workshop together; Emiliano is not in the room. The message of the afternoon, in order: a blueprint, a codelab, practice with a coding harness.

**What you need (slide 2).** Four cards, each one a link: these slides, the repository, the codelab and the credits. People open the deck on their laptop with the QR code of the cover and click from here. Say once, slowly, that there are two copies of the codelab: follow the one on GitHub Pages, use the Google-hosted one only to claim the credits.

**The app (slide 3).** A blog with posts and comments, on purpose: everybody knows the domain, so nothing distracts from what is behind it. The footer of the screenshot says where the app runs and where its files live.

**Behind it (slide 4).** Six things the app does and how. Each row is a part of the codelab: AI covers in Step 7, private uploads in Step 4, the three containers in Step 6, JSON logs from the first deploy in Step 3, secrets in Steps 5 and 6. The allow-list is one variable, `IAP_ALLOWED_USERS` (`.env.dist:42`, read by `blog/app/controllers/concerns/iap_authenticatable.rb:71` and turned into Terraform input by `iac/bin/terraform-apply.sh:44`); Identity-Aware Proxy itself is the optional Step 8.

**The problem (slide 5).** A default Rails 8 app keeps its state on disk, can run its jobs inside the web process (`blog/config/puma.rb:38`), and needs a master key. A platform that starts a clean container for every revision breaks all three. Attendees see it happen in Step 3 of the codelab.

**Stop 1, logs (slide 6).** `blog/config/environments/production.rb:44-52` picks the logger: the stock tagged logger when `LOG_FORMAT=plain`, otherwise a plain `ActiveSupport::Logger` on STDOUT with `GoogleJsonFormatter`. The formatter is one file of 68 lines: severity names at `blog/lib/google_json_formatter.rb:10-17`, the payload at `:24-28`, the trace id at `:32-40`, one JSON object per line at `:42`. A stack trace becomes one log entry.

**Stop 2, Solid trio and three containers (slide 7).** Solid Cache at `blog/config/environments/production.rb:64`, Solid Queue at `:67-68`, Solid Cable at `blog/config/cable.yml:11-12`. `blog/compose.prod.yaml` declares `web` (`:8`, the ingress container at `:12-13`), `worker` (`:32`, its command at `:36`) and `cloudsql-proxy` (`:53-54`). No Redis and no Kubernetes anywhere in the stack.

**Stop 3, private files (slide 8).** `blog/config/storage.yml:63-68`. The line that matters is `:67`, `iam: true`: Active Storage asks the IAM Credentials API to sign URLs, because a container on Cloud Run has an identity but no private key. The comment at `:1-17` tells the story. The bucket stays private, URLs expire, and there is no key file.

**Stop 4, database and secrets (slide 9).** `blog/config/database.yml:44-49` explains the three ways production finds its database. `:50` is the switch and `:51-57` builds the PostgreSQL connection from `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` and `DB_PASSWORD`. `blog/compose.prod.yaml:21-24` sets the four plain ones; the file carries no secret values (see its header, `:1-6`). The password and `RAILS_MASTER_KEY` are mounted from Secret Manager by one `gcloud run services update` in Step 6 of the codelab (`workshop/CODELAB.md`, section "Deploy 4b: Secrets from Secret Manager").

**Stop 5, AI job (slide 10).** Saving a post without a cover enqueues the job (`blog/app/models/post.rb:17`). The job is `blog/app/jobs/generate_cover_image_job.rb:9-31`; the AI part is `:15-16`, the attachment `:20-24`, the Turbo refresh `:28`. `blog/lib/nanobanana.rb:97-103` chooses between Vertex AI and the bundled placeholder cover; `:168-174` fetches Application Default Credentials; `:198-201` is the placeholder. No API key exists in the repository (`docs/CONSTITUTION.md`, section 11).

**The same blueprint elsewhere (slide 11).** One comparison slide. `docs/CONSTITUTION.md`, section 13, lists the files where provider-specific code is allowed. Read the small print on the slide out loud: only the Google Cloud column is built and tested in this repo.

**Kickoff (slides 12 to 16).** Any harness works: `AGENTS.md` is the instruction file, `CLAUDE.md` and `GEMINI.md` are symlinks to it, and `.claude/skills` and `.agents/skills` point to `skills/`. Show the codelab QR code until everyone has it open. The Google Cloud credits link is on page 2 of the codelab (Step 0); see the event page for which copy of the codelab shows the claim banner. Slide 16, "Questions welcome", stays up while people work.

**Closing (slides 17 and 18).** "Thank you" is the last slide of the talk: put it up at the wrap-up and remind people of the clean-up section at the end of the codelab. Slide 18 is a bonus picture of the three organisers of RubyCon Italy; show it only if the room is in the mood.

### Honest expectations to set

Measured on live runs on 18 Nov 2026:

- Each deploy that builds an image (`gcloud run deploy --source`, `gcloud run compose up`) takes about 6 minutes.
- Terraform in Step 1 takes about 6 to 12 minutes, mostly Cloud SQL. Tell people to start it and read ahead.
- Step 6 is two deploys. Deploy 4a brings up the three containers, still on SQLite and with no secrets. Deploy 4b mounts the two secrets on `web` and `worker` and switches to the dedicated service account. After 4b the service configuration contains only secret references.
- In the local Docker Compose stack a new post gets the bundled placeholder cover, because the containers hold no Google credentials. On Cloud Run the cover is generated by Vertex AI; it took about 3 minutes to appear.
- `just workshop-eval N` runs the checks of `workshop/skeleton.yaml` for Step N: mostly files and local tests, plus (in Step 5) whether the secrets and the database exist in the project. No eval asserts on the deployed Cloud Run service.

### If something goes wrong

- No network for the deck: export a PDF beforehand with `marp slides/rubyists.en.md --pdf --allow-local-files -o rubyists.pdf`.
- A stop runs long: skip slide 11, never the kickoff.
- A question about another cloud provider: the honest answer is on slide 11. The pattern transfers, the code in this repository is only tested on Google Cloud.

---

## Part 2: Attendee cheat-sheet

Open these files while the presenter talks, or later with your coding harness. Paths are relative to the repository root.

| Stop | Open | Look for |
|---|---|---|
| 1. Logs | `blog/config/environments/production.rb:48` | Four lines that swap the logger formatter |
| 1. Logs | `blog/lib/google_json_formatter.rb:24` | The payload: severity, time, message |
| 2. Jobs, cache, cable | `blog/config/environments/production.rb:64` | Solid Cache; Solid Queue follows at `:67` |
| 2. Three containers | `blog/compose.prod.yaml:7` | `web`, `worker`, `cloudsql-proxy` |
| 3. Storage | `blog/config/storage.yml:67` | `iam: true` |
| 4. Database | `blog/config/database.yml:51` | A connection built from five environment variables |
| 4. Secrets | `blog/compose.prod.yaml:21` | `DB_HOST: cloudsql-proxy`, and no password |
| 5. AI job | `blog/app/jobs/generate_cover_image_job.rb:15` | Two lines of AI in a 32-line job |
| 5. AI job | `blog/lib/nanobanana.rb:97` | Vertex AI, or the placeholder cover |

### Questions to ask your harness

Paste one of these into Claude Code, Codex, Gemini CLI, Antigravity or whatever you use. They are a good first test of how well it reads a codebase.

```text
Read blog/lib/google_json_formatter.rb and blog/config/environments/production.rb.
What would I change to send the same one-line JSON logs to a different log collector?
```

```text
Read blog/compose.prod.yaml and blog/config/database.yml.
Explain how the web container reaches PostgreSQL in production, and where the password comes from.
```

```text
Read blog/config/storage.yml. What does `iam: true` change compared with a JSON key file,
and which permission does the service account need for it?
```

```text
Read blog/lib/nanobanana.rb and blog/app/jobs/generate_cover_image_job.rb.
What happens when I create a post on my laptop with no Google credentials?
```

### Commands you will use all afternoon

```bash
just                    # list every recipe
just workshop-test      # pre-flight diagnostics for your machine
just workshop-eval 3    # automated checks for Step 3 (not a check of your deployed service)
```

The rules of the repository, for you and for your agent, are in [`docs/CONSTITUTION.md`](../../../docs/CONSTITUTION.md).
