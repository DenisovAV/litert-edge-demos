// SKILL.md files the skills tests drop into the skills folder at run time
// (wiring §2.1, §8): never bundled. Plain Dart so the unit tests import the
// same text the integration test writes.

/// The runtime-only example skill: composes `current_time` under a new
/// trigger and a new way of saying it, without code.
const kidClockSkillMd = '''
---
name: kid-clock
description: Tell the time the way you would to a small child, when the user asks you to tell their kid or a child what time it is.
---
# Kid clock

## Instructions
Call the `run_intent` tool with intent `current_time` and parameters {}.
Then say the time in one short sentence a five-year-old understands, for example "It is quarter past six in the evening."
''';

/// No front matter at all: listed with its parse error.
const brokenSkillMd = '''
# Broken skill

This file has no front matter, so it has no name or description.
''';
