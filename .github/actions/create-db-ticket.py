import requests
from requests.auth import HTTPBasicAuth
import os

def check_existing_ticket(jira_username, jira_token, title):
    #Jira Specifics - NEEDS TO BE UPDATED BECAUSE OF ENDPOINT DEPRECATION: https://developer.atlassian.com/changelog/#CHANGE-2046
    jira_url = "https://company.atlassian.net/rest/api/2/search/jql"

    #Jira Auth
    token = HTTPBasicAuth(jira_username, jira_token)
    
    jql_statement = f'project = DB AND (summary ~ "{title}") AND (status != DONE)'
    query = {
        'jql': jql_statement,
    }

    try:
        response = requests.get(jira_url, params=query, auth=token)
        if response.status_code == 200:
            issues = response.json().get("issues", [])
            if issues:
                issue_id = issues[0].get("id")
                print(f"Existing Jira ticket found: {issue_id}")
                return issue_id
            else:
                print("No existing Jira ticket found.")
                return None
        else:
            print(f"Failed to check existing tickets. Status code: {response.status_code}")
    except Exception as e:
        print(f"Error occurred while creating Jira ticket: {e}")         

def create_jira_ticket(jira_username, jira_token, title, description):
    #Jira Specifics
    jira_url = "https://company.atlassian.net/rest/api/2/issue/"
    project_key = "DB"
    issue_type = "DB General Request"
    
    #Jira Auth
    token = HTTPBasicAuth(jira_username, jira_token)

    payload = {
        "fields": {
            "project": {"key": project_key}, # Project ID
            "issuetype": {"name": issue_type},
            "summary": title,
            "description": description,
            "customfield_11470": {"value": "No"},  # Downstream Impact
            "customfield_11612": [{"value": "DEV"},{"value": "STG"},{"value": "PROD"}],  # Environment
            "customfield_11613": [{"value": "US"},{"value": "EU"}], #Region
            "customfield_12405": {"value": "SQL Server"}, # Database
            "customfield_14389": {"value": "No"},  # PII/PHI
            "parent": {"key": "DB-11004"},  # Epic Link
        }
    }
    try:
        response = requests.post(jira_url, json=payload, auth=token)
        if response.status_code == 201:
            issue_key = response.json().get("key")
            ticket_link = f"https://company.atlassian.net/browse/{issue_key}"
            print(f"Jira ticket {issue_key} created successfully. Ticket Link: {ticket_link}")
            return ticket_link
        else:
            print(
                f"failed to create Jira ticket. Status code: {response.status_code}")
            print(response.text)
    except Exception as e:
        print(f"Error occurred while creating Jira ticket: {e}")

def jira_add_comment(jira_username, jira_token, issue_id, description):
    #Jira Specifics
    jira_url = f"https://company.atlassian.net/rest/api/2/issue/{issue_id}/comment"
    
    #Jira Auth
    token = HTTPBasicAuth(jira_username, jira_token)

    payload = {
        "body": f"{description}\n\nPlease review the changes and provide feedback.",
    }
    
    try:
        response = requests.post(jira_url, json=payload, auth=token)
        if response.status_code == 201:
            print("Comment added successfully.")
        else:
            print(f"Failed to add comment. Status code: {response.status_code}")
    except Exception as e:
        print(f"Error occurred while adding comment: {e}")

if __name__ == '__main__':
    repo = os.environ.get("REPO_NAME")
    repo = repo.replace('"','')
    head_ref = os.environ.get("HEAD_REF")
    head_ref = head_ref.replace('"','')
    pr_url = os.environ.get("PR_URL")
    pr_url = pr_url.replace('"','')
    sql_diffs = os.environ.get("SQL_DIFFS")
    sql_diffs = sql_diffs.replace('"','')
 

    jira_username = "jira_automation@company.com"
    jira_token = os.environ.get("JIRA_TOKEN_DB")

    title = f"Review for {repo} - {head_ref}"

    issue_id = check_existing_ticket(jira_username, jira_token, title)
    if issue_id and sql_diffs == "1":
        sql_files = os.environ.get("SQL_FILES")
        sql_files = sql_files.replace('"','')
        sql_files = sql_files.replace(" ", "\n")

        description = f"The following SQL files have changed:\n{sql_files}"
        jira_add_comment(jira_username, jira_token, issue_id, description)
        gha_output = "commented"
    elif issue_id is None:
        description = f"Review is needed by the DBA team for PR: {pr_url}"
        ticket_link = create_jira_ticket(jira_username, jira_token, title, description)
        gha_output = "created"
    else:
        gha_output = "no_action"    

    with open(os.environ.get("GITHUB_OUTPUT"), "a") as fh:
        print(f'jira_action={gha_output}', file=fh)
        if gha_output == "created":
            print(f'jira_ticket_link={ticket_link}', file=fh)