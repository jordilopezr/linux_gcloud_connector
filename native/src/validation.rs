use anyhow::{Result, anyhow};
use regex::Regex;
use lazy_static::lazy_static;

lazy_static! {
    // GCP Project ID: 6-30 chars, lowercase letters, digits, hyphens
    // Must start with letter, end with letter or digit
    static ref PROJECT_ID_REGEX: Regex = Regex::new(
        r"^[a-z]([a-z0-9-]{4,28}[a-z0-9])?$"
    ).unwrap();

    // GCP Zone: e.g., us-central1-a, europe-west1-b, asia-east1-c
    // Format: {region}-{location}{sublocation}-{zone_letter}
    static ref ZONE_REGEX: Regex = Regex::new(
        r"^[a-z]+-[a-z]+[0-9]+-[a-z]$"
    ).unwrap();

    // GCP Instance Name: 1-63 chars, lowercase letters, digits, hyphens
    // Must start with letter
    static ref INSTANCE_NAME_REGEX: Regex = Regex::new(
        r"^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$"
    ).unwrap();

    // Linux Username: Standard POSIX username format
    // Must start with lowercase letter or underscore
    // Can contain lowercase letters, digits, underscores, hyphens
    // 1-32 characters long
    static ref USERNAME_REGEX: Regex = Regex::new(
        r"^[a-z_][a-z0-9_-]{0,31}$"
    ).unwrap();
}

/// Validates a GCP project ID
///
/// # Rules
/// - 6-30 characters long
/// - Must start with a lowercase letter
/// - Can contain lowercase letters, digits, and hyphens
/// - Must end with a letter or digit
///
/// # Examples
/// ```
/// assert!(validate_project_id("my-project-123").is_ok());
/// assert!(validate_project_id("MyProject").is_err()); // uppercase not allowed
/// assert!(validate_project_id("123-project").is_err()); // must start with letter
/// ```
pub fn validate_project_id(project_id: &str) -> Result<()> {
    if project_id.is_empty() {
        return Err(anyhow!("Project ID cannot be empty"));
    }

    if !PROJECT_ID_REGEX.is_match(project_id) {
        return Err(anyhow!(
            "Invalid project ID '{}'. Must be 6-30 chars, lowercase letters/digits/hyphens, \
             start with letter, end with letter or digit",
            project_id
        ));
    }

    Ok(())
}

/// Validates a GCP zone name
///
/// # Rules
/// - Format: {region}-{location}{number}-{zone_letter}
/// - Example: us-central1-a, europe-west2-b
///
/// # Examples
/// ```
/// assert!(validate_zone("us-central1-a").is_ok());
/// assert!(validate_zone("europe-west1-b").is_ok());
/// assert!(validate_zone("invalid-zone").is_err());
/// ```
pub fn validate_zone(zone: &str) -> Result<()> {
    if zone.is_empty() {
        return Err(anyhow!("Zone cannot be empty"));
    }

    if !ZONE_REGEX.is_match(zone) {
        return Err(anyhow!(
            "Invalid zone '{}'. Expected format: region-location#-letter (e.g., us-central1-a)",
            zone
        ));
    }

    Ok(())
}

/// Validates a GCP instance name
///
/// # Rules
/// - 1-63 characters long
/// - Must start with a lowercase letter
/// - Can contain lowercase letters, digits, and hyphens
/// - Must end with a letter or digit (if length > 1)
///
/// # Examples
/// ```
/// assert!(validate_instance_name("my-vm-01").is_ok());
/// assert!(validate_instance_name("a").is_ok()); // single letter valid
/// assert!(validate_instance_name("VM-01").is_err()); // uppercase not allowed
/// assert!(validate_instance_name("vm-").is_err()); // can't end with hyphen
/// ```
pub fn validate_instance_name(instance_name: &str) -> Result<()> {
    if instance_name.is_empty() {
        return Err(anyhow!("Instance name cannot be empty"));
    }

    if instance_name.len() > 63 {
        return Err(anyhow!(
            "Instance name '{}' too long ({} chars). Maximum is 63 characters",
            instance_name,
            instance_name.len()
        ));
    }

    if !INSTANCE_NAME_REGEX.is_match(instance_name) {
        return Err(anyhow!(
            "Invalid instance name '{}'. Must start with lowercase letter, \
             contain only lowercase letters/digits/hyphens, and end with letter or digit",
            instance_name
        ));
    }

    Ok(())
}

/// Validates a Linux username for SFTP operations
///
/// # Rules
/// - 1-32 characters long
/// - Must start with a lowercase letter or underscore
/// - Can contain lowercase letters, digits, underscores, and hyphens
/// - Follows POSIX username standards
///
/// # Examples
/// ```
/// assert!(validate_username("jlopezre").is_ok());
/// assert!(validate_username("_service").is_ok());
/// assert!(validate_username("user-name_01").is_ok());
/// assert!(validate_username("../root").is_err()); // path traversal attempt
/// assert!(validate_username("User").is_err()); // uppercase not allowed
/// ```
pub fn validate_username(username: &str) -> Result<()> {
    if username.is_empty() {
        return Err(anyhow!("Username cannot be empty"));
    }

    if username.len() > 32 {
        return Err(anyhow!(
            "Username '{}' too long ({} chars). Maximum is 32 characters",
            username,
            username.len()
        ));
    }

    if !USERNAME_REGEX.is_match(username) {
        return Err(anyhow!(
            "Invalid username '{}'. Must start with lowercase letter or underscore, \
             contain only lowercase letters/digits/underscores/hyphens, max 32 chars",
            username
        ));
    }

    Ok(())
}

/// Sanitizes a zone string from GCP API response
///
/// GCP API returns zones as full URLs like:
/// "https://www.googleapis.com/compute/v1/projects/myproject/zones/us-central1-a"
///
/// This function extracts just the zone name and validates it.
pub fn sanitize_zone_from_url(zone_url: &str) -> Result<String> {
    let zone_name = zone_url
        .split('/')
        .last()
        .ok_or_else(|| anyhow!("Invalid zone URL format: {}", zone_url))?;

    // Validate the extracted zone name
    validate_zone(zone_name)?;

    Ok(zone_name.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_project_ids() {
        assert!(validate_project_id("my-project").is_ok());
        assert!(validate_project_id("my-project-123").is_ok());
        assert!(validate_project_id("a12345").is_ok());
        assert!(validate_project_id("project-with-many-hyphens-123").is_ok());
    }

    #[test]
    fn test_invalid_project_ids() {
        // Too short
        assert!(validate_project_id("abc").is_err());

        // Uppercase
        assert!(validate_project_id("MyProject").is_err());

        // Starts with number
        assert!(validate_project_id("123project").is_err());

        // Ends with hyphen
        assert!(validate_project_id("project-").is_err());

        // Contains underscore
        assert!(validate_project_id("my_project").is_err());

        // Empty
        assert!(validate_project_id("").is_err());

        // Too long (31 chars)
        assert!(validate_project_id("a123456789012345678901234567890").is_err());
    }

    #[test]
    fn test_valid_zones() {
        assert!(validate_zone("us-central1-a").is_ok());
        assert!(validate_zone("europe-west1-b").is_ok());
        assert!(validate_zone("asia-east1-c").is_ok());
        assert!(validate_zone("us-west2-a").is_ok());
    }

    #[test]
    fn test_invalid_zones() {
        assert!(validate_zone("invalid").is_err());
        assert!(validate_zone("us-central").is_err());
        assert!(validate_zone("US-CENTRAL1-A").is_err());
        assert!(validate_zone("").is_err());
        assert!(validate_zone("us_central1_a").is_err());
    }

    #[test]
    fn test_valid_instance_names() {
        assert!(validate_instance_name("my-vm").is_ok());
        assert!(validate_instance_name("a").is_ok());
        assert!(validate_instance_name("vm-01-test").is_ok());
        assert!(validate_instance_name("instance-with-many-hyphens").is_ok());
    }

    #[test]
    fn test_invalid_instance_names() {
        // Uppercase
        assert!(validate_instance_name("MyVM").is_err());

        // Starts with number
        assert!(validate_instance_name("1-vm").is_err());

        // Ends with hyphen
        assert!(validate_instance_name("vm-").is_err());

        // Contains underscore
        assert!(validate_instance_name("my_vm").is_err());

        // Empty
        assert!(validate_instance_name("").is_err());

        // Too long (64 chars)
        assert!(validate_instance_name(
            "a123456789012345678901234567890123456789012345678901234567890123"
        ).is_err());

        // Starts with hyphen
        assert!(validate_instance_name("-vm").is_err());
    }

    #[test]
    fn test_sanitize_zone_from_url() {
        // Valid GCP API URL
        let url = "https://www.googleapis.com/compute/v1/projects/my-project/zones/us-central1-a";
        assert_eq!(sanitize_zone_from_url(url).unwrap(), "us-central1-a");

        // Already just the zone name
        assert_eq!(sanitize_zone_from_url("us-west1-b").unwrap(), "us-west1-b");

        // Invalid zone in URL
        assert!(sanitize_zone_from_url("https://example.com/invalid-zone").is_err());
    }

    #[test]
    fn test_valid_usernames() {
        assert!(validate_username("jlopezre").is_ok());
        assert!(validate_username("_service").is_ok());
        assert!(validate_username("user01").is_ok());
        assert!(validate_username("user-name_01").is_ok());
        assert!(validate_username("a").is_ok());
    }

    #[test]
    fn test_invalid_usernames() {
        // Uppercase
        assert!(validate_username("User").is_err());
        assert!(validate_username("ROOT").is_err());

        // Starts with number
        assert!(validate_username("1user").is_err());

        // Starts with hyphen
        assert!(validate_username("-user").is_err());

        // Path traversal attempts
        assert!(validate_username("../root").is_err());
        assert!(validate_username("..").is_err());

        // Contains invalid characters
        assert!(validate_username("user@host").is_err());
        assert!(validate_username("user.name").is_err());
        assert!(validate_username("user/admin").is_err());

        // Empty
        assert!(validate_username("").is_err());

        // Too long (33 chars)
        assert!(validate_username("a12345678901234567890123456789012").is_err());
    }

    #[test]
    fn test_command_injection_attempts() {
        // These should all be rejected
        assert!(validate_instance_name("vm; rm -rf /").is_err());
        assert!(validate_instance_name("vm && whoami").is_err());
        assert!(validate_instance_name("vm | cat /etc/passwd").is_err());
        assert!(validate_instance_name("vm`whoami`").is_err());
        assert!(validate_instance_name("vm$(whoami)").is_err());
        assert!(validate_project_id("project; drop table users").is_err());
        assert!(validate_zone("us-central1-a; ls -la").is_err());
        assert!(validate_username("user; rm -rf /").is_err());
        assert!(validate_username("user`whoami`").is_err());
    }
}
