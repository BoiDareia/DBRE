# Flyway Migration Automation Script

This PowerShell script is designed to automate **Flyway database migrations**. It simplifies the process by reading settings from a configuration file and preparing the necessary commands to run Flyway. This makes deployments more consistent and less prone to manual errors. ⚙️

The script is split into two main functions.

---

## 1. LoadEnvironmentDetails

This function's job is to **read a configuration file**. This file can be in either **JSON** or **XML** format and contains important settings like the database connection string and paths to SQL script files.

It checks to make sure the file exists before trying to read it. If it’s successful, it passes all the loaded settings on to the next function.

---

## 2. ExecuteFlywayCreate

This is the core function of the script. It takes the configuration details from the first function and prepares everything needed to run the Flyway migration command.

Its key tasks include:
- **Parsing the Version**: It can figure out the correct migration version number even if it's part of a Git branch name (like `feature/v1.2.3`) or a tag.
- **Handling Credentials**: It securely uses the provided username and password to connect to the database.
- **Building the Command**: It assembles the final Flyway command string with all the correct options, like the target version, baseline version, and other settings.
- **Logging**: It logs the command it's about to run (with the password hidden) so you have a record of what happened.
- **Error Safety**: If a migration fails, the script will automatically **rename the failed SQL file**. This is a safety measure to prevent the broken script from being run again automatically on the next attempt.

In short, this function acts as a smart builder, putting together a precise and safe Flyway command tailored to the specific deployment. 🚀