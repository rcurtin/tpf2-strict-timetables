function data()
  return {
    en = {
      ["mod_name"] = "Strict Timetables",
      ["mod_description"] = "Strict Timetables allows specific and strict departure times to be set for vehicles on an entire line.",
      ["timetable"] = "Timetable",
      ["timetables"] = "Timetables",
      ["lines"] = "Lines",
      ["filter:"] = "Filter:",
      ["none"] = "None",
      ["debug_tooltip"] = "Debug mode: when enabled, print timetables to stdout every time they change, and print vehicle events.",
      ["unassigned vehicles:"] = "Unassigned vehicles:",
      -- used in the unassigned vehicle dialog; note the spacing
      ["stopped"] = "stopped",
      ["stopped at station"] = "stopped at station",
      ["en route"] = "en route)",
      ["stopped at "] = "stopped at ",
      ["en route to "] = "en route to ",
      ["unknown vehicle"] = "unknown vehicle",
      ["not assigned to a line"] = "not assigned to a line",
      ["unknown line"] = "unknown line",
      ["unknown station"] = "unknown station",
      -- used for tooltips in the timetable editing dialog.
      ["remove_slot"] = "Remove this timetable slot (all entries in this column).",
      ["add_entry"] = "Add a timetable entry.",
      ["remove_entry"] = "Remove this timetable entry.",
      ["duplicate_text"] = "Duplicate timetable:",
      ["max_lateness"] = "Maximum lateness:",
      ["max_lateness_tooltip"] = "Trains later than this will be considered early (so e.g. if set\nto 30 minutes, a train that is 45 minutes late will actually be\nconsidered 15 minutes early, and will wait for 15 minutes until\nbeing released.  Similarly, a train arriving 45 minutes early will\nactually be considered 15 minutes late and immediately\nreleased!)",
      ["apply"] = "Apply!",
      ["apply_tooltip"] = "Apply the timetable spacing with the selected spacing.\n(If no spacing is selected, nothing happens.)\n\nThis will *overwrite* every slot in the existing timetable\nafter the first with new timeslots that have the specified\nspacing from the original."
    }
  }
end
