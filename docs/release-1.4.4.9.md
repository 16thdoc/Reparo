# Reparo 1.4.4.9

- Fix a false npm ownership failure in Windows PowerShell: prefix/version/root
  probes now drain native output before selecting a line and preserve the real
  root-probe exit. Genuine root failures still block package updates.
- Classify the WSL cleanup probe's known new-workload signal as intentional
  preservation. Keep its raw exit 3, show preserved-workload counts, and avoid
  labeling completed apt work failed or pending because cleanup was deferred.
  Unknown state, timeouts and unrelated failures remain visible and fail closed.
- Keep human and manual AI summaries aligned. No historical receipt rewrite,
  package-operation retry, syslog behavior change or controller guard bypass.

Regression coverage includes real disposable native shims, large probe output,
genuine nonzero probes, harmless native exit 3, explicit cleanup context,
uncertain cleanup, and human/AI/finality agreement. Windows/native version,
attributable quote and text art match. Existing runtime/configuration/lock and
deployment safeguards remain in place.
