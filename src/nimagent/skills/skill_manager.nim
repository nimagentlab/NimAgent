import std/[os, strutils]

type
  Skill* = object
    name*: string
    content*: string
    category*: string

  SkillManager* = ref object
    skills*: seq[Skill]
    skillDir*: string
    loaded*: bool

proc newSkillManager*(skillDir: string = "skills"): SkillManager =
  SkillManager(skills: @[], skillDir: skillDir, loaded: false)

proc loadSkills*(sm: SkillManager) =
  ## Loads all .md files from the skills directory.
  ## If already loaded, does nothing (use reloadSkills() to force).
  if sm.loaded: return
  sm.skills = @[]
  if not dirExists(sm.skillDir): return
  for kind, path in walkDir(sm.skillDir):
    if kind == pcFile and path.endsWith(".md"):
      let name = extractFilename(path).changeFileExt("")
      sm.skills.add(Skill(
        name: name,
        content: readFile(path),
        category: "general"
      ))
  sm.loaded = true

proc reloadSkills*(sm: SkillManager) =
  ## Forces reloading skills from disk.
  sm.loaded = false
  sm.loadSkills()

proc getSkillPrompt*(sm: SkillManager): string =
  ## Generates the prompt block to inject with all active skills.
  if sm.skills.len == 0: return ""
  result = "\n--- ACTIVE SKILLS ---\n"
  for skill in sm.skills:
    result &= "\n### " & skill.name & "\n" & skill.content & "\n"
  result &= "--- END SKILLS ---\n"

proc getSkill*(sm: SkillManager, name: string): string =
  ## Retrieves a skill by name.
  for skill in sm.skills:
    if skill.name == name: return skill.content
  return ""
