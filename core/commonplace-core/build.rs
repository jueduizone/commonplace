fn main() {
    let hash = std::process::Command::new("git")
        .args(["describe", "--always", "--dirty", "--exclude", "*"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "dev".into());
    println!("cargo:rustc-env=CP_BUILD={hash}");
    // Resolve the worktree-specific Git path; .git is a file in a linked worktree.
    // The reflog changes on every commit, even when the branch name stays the same.
    if let Ok(output) = std::process::Command::new("git")
        .args(["rev-parse", "--git-path", "logs/HEAD"])
        .output()
    {
        if output.status.success() {
            println!("cargo:rerun-if-changed={}", String::from_utf8_lossy(&output.stdout).trim());
        }
    }
}
