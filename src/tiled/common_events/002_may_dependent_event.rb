# Common event 2: May dependent event
common(
  id: 2,
  name: "May dependent event",
  trigger: :none,
  switch: 1,
  commands: [
    text("\\rDo you want me to stop following you?"),
    *show_choices(
      choices: ["Yes", "No"],
      cancellation: 2,
      choice1: [
        text("\\rI'll just vanish, then."),
        script("Followers.remove(\"May\")"),
        script("pbDeregisterPartner"),
      ],
      choice2: [
        text("\\rLet's keep going!"),
      ],
    ),
  ],
)
