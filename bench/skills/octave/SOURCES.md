# Sources

- https://octave.org/NEWS-11.html: Octave 11 changes: the cellfun type error, mean/stat input restrictions, "all"/vecdim/nanflag options, qr one-output R, polyfit rsquared and S.X deprecation, colorbar location order, pkg install/search changes, new functions (rms, rmse, mape, xline, yline, assert_equal, _Exit), and the 11.2/11.3 fixes.
- https://octave.org/news/release/2026/06/01/octave-11.3.0-released.html: 11.3.0 is a minor fix release over 11.2.0 (liboctinterp SOVERSION).
- https://www.octave.org/NEWS-10.html: Octave 10 changes: removal of shift, fminsearch extra-args and load -force/-import, dsearch deprecation, non-integer size errors, C++17 requirement, new CLI short options (-e, -g, -G, --no-init-*).
- https://wiki.octave.org/Octave_style_guide: official style: 2-space indent, # comments, endXXX keywords, ! and !=, double quotes, spacing before call parens, naming, error message prefixes.
- https://wiki.octave.org/Compatibility: Octave vs MATLAB differences: no string class, partial classdef, nested-function scoping, short-circuit rules.
- https://docs.octave.org/latest/Test-Functions.html: %!test/%!assert/%!error/%!warning/%!shared/%!xtest block syntax and test() calling forms and outputs.
- https://docs.octave.org/latest/Creating-Packages.html: package tarball layout (DESCRIPTION, inst/, src/, COPYING).
- https://docs.octave.org/latest/The-DESCRIPTION-File.html: DESCRIPTION fields and Depends semantics.
- https://github.com/matlab/rules: published AI-assistant rules for MATLAB (validation, vectorization, preallocation, no eval). Used to identify what agents carry over from MATLAB that must be adapted (e.g. `arguments` blocks, which Octave ignores).
- https://scivision.dev/windows-matlab-octave-continuous-integration: common CI practice: install Octave via apt/winget and run `octave --eval` on a test script.
- https://hub.docker.com/r/gnuoctave/octave: official Docker images used for package CI.
- Installed toolchain (Octave 11.3.0, Homebrew, macOS arm64): every API, flag and error message in SKILL.md was checked by running snippets: `octave-cli --help`, `help pkg`, `help cellfun`, `help assert_equal`, `mkoctfile --help`, building .oct/.mex files, installing and testing a sample package with `pkg prefix`/`pkg install`/`pkg test`, plus classdef, test-block and runtime-error probes.
