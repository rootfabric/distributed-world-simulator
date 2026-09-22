# Exact canonical baseline: M5/M6 diagnostics

Чистый исходный main6982a563/tree97c61acc96f507d71b6883fbdeef486c08b1113d,
canonical Windows double Godot. Без временного runtime overlay; новый worktree
импортирован один раз при свободном9080, затем отдельный isolated user profile.

M5 graphical multiplayer acceptance:101 assertions /0 failures, exit0,
два ERROR PeekNamedPipe в cleanup `_finish`/`_observe_process_exit`.
M6 dedicated recovery contracts:126 assertions /0 failures, exit0,
WARNING8 ObjectDB instances и ERROR4 resources still in use.

Те же diagnostics появились при полном world/core candidate3b82145a.
Независимый Reviewer классифицировал их как воспроизведённый preexisting
baseline debt. Это не утверждение harmless/fatal-clear и не full-world PASS.
Source этих тестов не исправлялся и assertions не ослаблялись. Для full-world
итога требуется завершение327 tests и отдельное review/verifier addendum.

`provenance.json` связывает команды, exact baseline identity и SHA256 raw logs.
