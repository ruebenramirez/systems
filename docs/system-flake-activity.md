# System flake activity

The chart covers the trailing 36 months (12 quarters) of commits and labels the
quarter when each machine was added to `nixosConfigurations`. Removed machines
remain in the historical timeline.

![Quarterly system flake commit volume and machine additions](system-flake-commit-volume.svg)

[Mermaid source](system-flake-commit-volume.mmd)

## Regenerating the chart

Run these commands from the repository root:

```shell
scripts/generate-system-flake-chart.sh               # rewrite docs/system-flake-commit-volume.mmd
scripts/generate-system-flake-chart.sh --render      # render the SVG and auto-fit the labels
scripts/generate-system-flake-chart.sh --all         # chart full history since the fork
scripts/generate-system-flake-chart.sh --quarters 8  # override the most recent 12-quarter window
```

The script derives quarterly commit volume from git author dates
(`ce788b1^..master`) and appends the machine-addition labels from a table in the
script. Machine labels only appear when their add-quarter falls inside the
window. Pass a different ref as an argument to chart another branch or commit.
