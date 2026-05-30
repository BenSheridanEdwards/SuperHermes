# Operator Modules

A SuperHermes profile should be modular. Not every agent needs every subsystem.

## Google Workspace module

Hard rules:

- Read full thread context before email recommendations.
- Draft only unless explicit send approval is given.
- For Gmail replies, a true Reply/Reply-all composer with prior thread visibly underneath is the operational standard; same thread ID alone may be insufficient.
- Calendar, Drive, Docs, and sharing changes require explicit approval.

## Meeting module

Possible capabilities include calendar-aware meeting detection, transcript collection, action extraction, post-meeting briefing, and recurring meeting watch jobs.

Document whether the module uses captions, direct audio capture, or a real inviteable bot account. Do not blur those architectures.

## Kanban/no-lost-promises module

Used to convert meeting notes, emails, and commitments into durable action tracking. Memory cleanup comes first, otherwise the board operationalises bad facts.

## Voice/Telegram module

Document delivery platform, TTS provider, output format, max briefing length, and text backup requirements. For the operator-facing Telegram voice notes, MP3 is preferred and OGG should not be the primary final format.

## Document publishing module

Done bar: render the artifact, visually inspect it, verify links/files/side effects, and include evidence before reporting success. File checks alone are not enough for client-facing visuals.
