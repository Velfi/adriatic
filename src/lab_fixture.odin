package main

// Durable fixture configuration for authoring labs. Runtime scene identity and
// generated lab state remain on Editor.
Lab_Kind :: enum u8 {
    None,
}

Lab_Fixture_State :: struct {
    kind: Lab_Kind,
}

// Return the precise durable-state path which prevents a lab from being
// rehydrated. This does no allocation and is safe before an Editor mutation.
lab_fixture_preflight :: proc(lab: Lab_Fixture_State) -> string {
    return lab.kind == .None ? "" : "lab.kind"
}
