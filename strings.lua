function data()
  return {
    en = {
      ["mod_name"] = "Strict Timetables",
      -- See also description.txt.
      ["mod_description"] = [[
[h1]Strict Timetables[/h1]

This is a mod for Transport Fever 2 that aims to improve upon the excellent work of @IncredibleHannes, @Gregory365, and others who worked on the Timetables mod (https://github.com/Gregory365/TPF2-Timetables).

In essence the goal of this mod is to provide a better interface for strict timetables: in the original Timetables mod, a vehicle would be assigned to a departure time slot whenever it arrived at a station.  However, you can get some really bad problems when trains are late, because they will end up in the departure time slot that was actually intended for the [i]next[/i] train, and this can cause all kinds of havoc on mainlines.

Therefore the timetabling strategy here is [b]strict[/b]:

[b]1.[/b] At the beginning of a line, a vehicle is assigned to a time slot for departure from the first timetabled station.

[b]2.[/b] This time slot is specific to the entire route: so, e.g., if the first timed departure from the first station is set at 00:00, and the first timed departure from the second station is set at 11:00, a vehicle that gets the 00:00 departure from the first station will be assigned to the 11:00 first departure from the second station (and the first departure time slot from all subsequent stations).

[b]3.[/b] If a vehicle arrives after its scheduled departure time, it will leave immediately (after unloading and loading, with a maximum of 10 seconds for a full load stop) in an attempt to make up for lost time.

Note that there are [b]no arrival times[/b] in this mod; you only set the departure times at each stop.  Therefore, you might want to consider adding enough "slack" in the schedule to account for delays between stations (or just make sure that delays don't happen!).
]],
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
