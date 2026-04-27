# Xyra Community Tools

Open source tools for securing AI agent behavior in enterprise environments.
Built by the team at [Xyra Security](https://xyraSecurity.ai), free to use and contribute to.

---

## What is this?

AI coding agents like Cursor, Claude Code, and Codex are being deployed across enterprise environments with access to production infrastructure, credentials, and sensitive data.

The security tooling hasn't kept up.

This repo is our contribution to closing that gap. Each tool here addresses a specific, real-world AI agent risk - documented from incidents we've observed in the field and from public disclosures across the industry.

These tools are independent of the Xyra platform. No account required. No telemetry. Just security tooling you can inspect, deploy, and contribute to.

---

## Tools

### hooks/block-hooks

Installs a pre-execution hook on Cursor, Claude Code, and Codex that intercepts shell commands and MCP tool calls before they run. Blocks destructive operations based on configurable keywords defined in `keywords.txt`.

**Motivation:** On April 23, 2026, a Cursor agent running Claude Opus 4.6 deleted a production database and all volume-level backups in a single 9-second API call. The agent violated its own safety rules and produced a written confession afterward. This hook would have blocked the operation before it fired.

[Read more and install](./hooks/block-hooks/README.md)

---

## Philosophy

System prompts are advisory. Models read the rules, acknowledge them, and sometimes violate them anyway - because there is nothing enforcing them at the execution layer.

These tools operate at the execution layer.

They are not a replacement for a full AI security platform. They are a first line of defense that any team can deploy in minutes, for free, without vendor lock-in.

---

## Disclaimer

These tools are provided "as is" without warranty of any kind. Use at your own risk. Xyra Security Ltd. and contributors are not liable for any damages, data loss, or security incidents that occur while using these tools.

These tools provide one layer of defense and do not replace proper security practices including access controls, token scoping, backups, monitoring, and human review of critical operations. Test thoroughly before production deployment.

---

## Contributing

Found a new AI agent risk? Built a hook for a different destructive operation? We welcome contributions.

1. Fork the repo
2. Create a folder under the relevant category (`hooks/`, `detections/`, `policies/`)
3. Include a `README.md` explaining the risk, the motivation, and installation steps
4. Open a pull request

Please include a real-world incident reference or documented risk scenario where possible. Tools with clear motivation get merged faster.

---

## License

Apache License 2.0. Use it, fork it, ship it.

See [LICENSE](./LICENSE) for the full text.

---

## About Xyra Security

Xyra Security is an AI agent security platform for enterprise environments. We provide observability, detection, and response for AI coding tools, MCP servers, and agentic workflows.

[xyraSecurity.ai](https://xyraSecurity.ai)
