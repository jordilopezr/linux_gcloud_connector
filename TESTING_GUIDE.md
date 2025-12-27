# SFTP Security Testing Guide - v1.7.0

**Date:** 2025-12-26
**Purpose:** Verify all 11 security fixes from SECURITY_AUDIT.md

---

## Prerequisites

1. **Start the app:**
   ```bash
   ./build/linux/x64/debug/bundle/linux_cloud_connector
   ```

2. **Have a running GCP VM instance** with:
   - Status: RUNNING
   - SSH access configured
   - IAP tunnel permissions

3. **Monitor console logs** for detailed error messages

---

## Test #1: Path Traversal Protection ⚠️ CRITICAL

**What we're testing:** Rust-side validation prevents accessing files outside /home/{username}

### Test 1.1: Direct Path Traversal (MUST FAIL)
**How to trigger:** This is automatically blocked at the Rust level before even making SFTP calls.

**Expected Result:**
- ❌ Cannot navigate outside user's home directory
- ✅ Rust validation rejects ".." components

**Verification:**
```bash
# Check console logs for:
# "Path traversal attempt detected"
# "Access denied: path outside user directory"
```

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test #2: Directory Name Validation 🛡️ HIGH

**What we're testing:** UI-side validation prevents injection via directory names

### Test 2.1: Slash in Directory Name (MUST FAIL)
1. Open SFTP browser
2. Click "New Folder"
3. Enter: `foo/bar`
4. Click "Create"

**Expected Result:**
- ❌ Error: "Directory name cannot contain path separators (/ or \)."
- ✅ Directory NOT created

### Test 2.2: Parent Directory Reference (MUST FAIL)
1. Click "New Folder"
2. Enter: `../evil`
3. Click "Create"

**Expected Result:**
- ❌ Error: "Directory name cannot contain '..' (parent directory references)."

### Test 2.3: Empty Name (MUST FAIL)
1. Click "New Folder"
2. Enter: `   ` (just spaces)
3. Click "Create"

**Expected Result:**
- ❌ Error: "Directory name cannot be empty."

### Test 2.4: Very Long Name (MUST FAIL)
1. Click "New Folder"
2. Enter: 300 characters (e.g., "a" repeated 300 times)
3. Click "Create"

**Expected Result:**
- ❌ Error: "Directory name too long (max 255 characters)."

### Test 2.5: Valid Directory Name (MUST PASS)
1. Click "New Folder"
2. Enter: `test-folder-123`
3. Click "Create"

**Expected Result:**
- ✅ Directory created successfully
- ✅ Appears in file list

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test #3: Filename Sanitization 🔒 MEDIUM

**What we're testing:** Uploaded filenames are sanitized to prevent command injection

### Test 3.1: Create Dangerous Filename Locally
```bash
# Create a test file with dangerous characters
cd /tmp
touch 'test;rm -rf.txt'
touch 'report$(whoami).pdf'
touch 'file|cat passwd.txt'
```

### Test 3.2: Upload Dangerous File (MUST SANITIZE)
1. In SFTP browser, click "Upload"
2. Select: `test;rm -rf.txt`
3. Upload

**Expected Result:**
- ✅ File uploaded successfully
- ✅ Filename sanitized to: `test_rm -rf.txt` (or similar, with `;` replaced)
- ❌ No command execution

**Verification:**
```bash
# Check the actual filename on remote server:
ssh your-vm "ls -la ~/"
# Should show sanitized filename, not original
```

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test #4: File Size Limits 🚫 HIGH

**What we're testing:** Transfers abort if file exceeds 10GB

### Test 4.1: Create Large Test File
```bash
# Create a 100MB test file (safe size)
dd if=/dev/zero of=/tmp/test_100mb.bin bs=1M count=100

# Create an 11GB test file (exceeds limit) - OPTIONAL if you have space
# dd if=/dev/zero of=/tmp/test_11gb.bin bs=1G count=11
```

### Test 4.2: Upload 100MB File (MUST PASS)
1. In SFTP browser, click "Upload"
2. Select: `/tmp/test_100mb.bin`
3. Upload

**Expected Result:**
- ✅ Upload succeeds
- ✅ File appears in remote directory

### Test 4.3: Upload 11GB File (MUST FAIL)
**⚠️ Skip this if you don't have disk space**

1. Click "Upload"
2. Select: `/tmp/test_11gb.bin`
3. Upload

**Expected Result:**
- ❌ Error: "File size exceeds maximum allowed size of 10 GB"
- ✅ Console log shows: "Transfer aborted"
- ✅ Partial file deleted (or not created)

### Test 4.4: Download Large File (MUST FAIL if > 10GB)
**If you have a file > 10GB on the remote server:**

1. Select large file
2. Click download icon

**Expected Result:**
- ❌ Error: "File size exceeds maximum"
- ✅ Download aborted

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test #5: Parent Directory Navigation 🧭 MEDIUM

**What we're testing:** "Up" button allows navigation to parent directory

### Test 5.1: Navigate Into Subdirectory
1. Create a test folder: `testdir`
2. Double-click to enter `testdir`
3. Verify current path shows: `/home/{username}/testdir`

### Test 5.2: Navigate Up (MUST WORK)
1. Click the "↑" (up arrow) button in toolbar
2. Verify current path returns to: `/home/{username}`

### Test 5.3: Up Button Disabled at Home (MUST BE DISABLED)
1. Navigate to: `/home/{username}`
2. Verify "↑" button is DISABLED (grayed out)
3. Tooltip should show: "Go to parent directory"

**Expected Result:**
- ✅ Cannot navigate above user's home directory
- ✅ Up button works in subdirectories
- ✅ Up button disabled at home

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test #6: SSH Authentication Error Messages 📋 MEDIUM

**What we're testing:** Detailed error messages when SSH auth fails

### Test 6.1: Disable SSH Agent
```bash
# Temporarily kill ssh-agent
killall ssh-agent
# or
unset SSH_AUTH_SOCK
```

### Test 6.2: Rename SSH Key (Make it Unavailable)
```bash
mv ~/.ssh/id_rsa ~/.ssh/id_rsa.backup
```

### Test 6.3: Try SFTP Connection (MUST FAIL WITH DETAILS)
1. Open app
2. Select a running instance
3. Click "Open SFTP"

**Expected Result:**
- ❌ SFTP browser doesn't open
- ✅ Error message shows:
  ```
  All SSH authentication methods failed:
    • SSH agent: [specific error]
    • SSH key file not found at: /home/you/.ssh/id_rsa

  Please either:
    1. Start ssh-agent and add your key: ssh-add ~/.ssh/id_rsa
    2. Create an SSH key pair: ssh-keygen -t rsa
    3. Ensure your public key is in the remote server's ~/.ssh/authorized_keys
  ```

### Test 6.4: Restore SSH Setup
```bash
mv ~/.ssh/id_rsa.backup ~/.ssh/id_rsa
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
```

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test #7: Tunnel Error Handling 🔧 CRITICAL

**What we're testing:** Clear error messages when tunnel creation fails

### Test 7.1: Stop Instance
1. In GCP Console, **STOP** your test VM instance
2. Wait until status is "TERMINATED"

### Test 7.2: Try SFTP on Stopped Instance (MUST FAIL WITH MESSAGE)
1. In app, select the stopped instance
2. Click "Open SFTP"

**Expected Result:**
- ❌ SFTP browser doesn't open
- ✅ Error message appears:
  ```
  Failed to create SSH tunnel for SFTP.

  Please verify:
  • Instance is RUNNING
  • You have IAP tunnel permissions
  • Network connectivity is working
  • gcloud CLI is authenticated
  ```
- ✅ "Retry" button available in error message

### Test 7.3: Restart Instance & Retry
1. Start the instance in GCP Console
2. Wait until status is "RUNNING"
3. Try SFTP again

**Expected Result:**
- ✅ SFTP browser opens successfully

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test #8: Exception Handling & Logging 📊 CRITICAL

**What we're testing:** Specific exception types are caught and logged correctly

### Test 8.1: Check Console Logs
1. Perform any SFTP operation (e.g., create folder)
2. Check terminal output

**Expected Result:**
- ✅ Structured logging format:
  ```
  ═══ SFTP ERROR: [Operation] ═══
  Operation: [action]
  Host: localhost:XXXXX
  Username: [user]
  Error Type: [type]
  Error Message: [msg]
  Stack Trace:
  [trace]
  ═══════════════════════════════
  ```

### Test 8.2: Trigger Network Error
1. While SFTP browser is open, disconnect network
2. Try to upload a file

**Expected Result:**
- ❌ Operation fails
- ✅ Error message in UI: "Failed to upload '[filename]': [error]"
- ✅ Console shows full stack trace
- ✅ Error categorized as Exception (not unexpected)

### Test 8.3: Memory Leak Verification (TextEditingController)
1. Open SFTP browser
2. Click "New Folder" → Cancel (20 times)
3. Monitor memory usage

**Expected Result:**
- ✅ Memory doesn't continuously grow
- ✅ Controllers properly disposed (check logs if debug enabled)

**Status:** ⬜ PASS / ⬜ FAIL

---

## Regression Testing: Normal Operations 🔄

**Verify that security fixes didn't break normal functionality**

### RT-1: Upload Normal File
- ✅ Upload a regular file (e.g., `document.pdf`)
- ✅ File appears in list
- ✅ Correct size displayed

### RT-2: Download Normal File
- ✅ Download a file
- ✅ File saved to chosen directory
- ✅ File contents intact (verify checksum if possible)

### RT-3: Create Normal Directory
- ✅ Create folder: `my-project-files`
- ✅ Folder created successfully
- ✅ Can navigate into it

### RT-4: Delete File/Folder
- ✅ Delete a test file
- ✅ Confirmation dialog appears
- ✅ File removed from list

### RT-5: Large File Transfer (< 10GB)
- ✅ Upload/download 1GB+ file
- ✅ Transfer completes successfully
- ✅ No errors or crashes

**Status:** ⬜ PASS / ⬜ FAIL

---

## Test Summary

| Test # | Name | Priority | Status |
|--------|------|----------|--------|
| 1 | Path Traversal Protection | CRITICAL | ⬜ PASS / ⬜ FAIL |
| 2 | Directory Name Validation | HIGH | ⬜ PASS / ⬜ FAIL |
| 3 | Filename Sanitization | MEDIUM | ⬜ PASS / ⬜ FAIL |
| 4 | File Size Limits | HIGH | ⬜ PASS / ⬜ FAIL |
| 5 | Parent Navigation | MEDIUM | ⬜ PASS / ⬜ FAIL |
| 6 | SSH Auth Errors | MEDIUM | ⬜ PASS / ⬜ FAIL |
| 7 | Tunnel Error Handling | CRITICAL | ⬜ PASS / ⬜ FAIL |
| 8 | Exception Handling | CRITICAL | ⬜ PASS / ⬜ FAIL |
| RT | Regression Testing | ALL | ⬜ PASS / ⬜ FAIL |

---

## Known Limitations

1. **Path Traversal Test:** Cannot easily test from UI because Rust blocks it before SFTP calls
   - **Alternative:** Trust Rust unit tests (could add them)

2. **10GB File Test:** Requires significant disk space
   - **Alternative:** Test with smaller limit in code (e.g., 100MB for testing)

3. **SSH Auth Test:** Requires temporarily disabling SSH
   - **Warning:** Make sure you can restore access!

---

## Post-Testing Cleanup

```bash
# Remove test files
rm -f /tmp/test_*.bin
rm -f /tmp/test\;*.txt

# Restore SSH if modified
mv ~/.ssh/id_rsa.backup ~/.ssh/id_rsa 2>/dev/null
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

# Clean up remote test files (via SSH)
ssh your-vm "rm -f ~/test* && rmdir ~/testdir 2>/dev/null"
```

---

## Reporting Issues

If any test **FAILS**, please note:
1. Test number and name
2. Expected vs Actual behavior
3. Console log output
4. Steps to reproduce

---

**Testing completed by:** _____________
**Date:** _____________
**Overall Status:** ⬜ ALL PASS / ⬜ SOME FAILURES
