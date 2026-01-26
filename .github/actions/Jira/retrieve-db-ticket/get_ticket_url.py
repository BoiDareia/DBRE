import requests
from requests.auth import HTTPBasicAuth
import os

def check_existing_ticket(jira_username, jira_token, jql_statement):
    #Jira Specifics
    jira_url = "https://company.atlassian.net/rest/api/3/search/jql"

    #Jira Auth
    token = HTTPBasicAuth(jira_username, jira_token)

    headers = {
        "Accept": "application/json"
    }
    
    query = {
        'jql': jql_statement,
    }

    try:
        response = requests.get(jira_url, headers=headers, params=query, auth=token)
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

def get_ticket_url(jira_username, jira_token,issue_id):
    #Jira Specifics
    jira_url = f"https://company.atlassian.net/rest/api/3/issue/{issue_id}"

    #Jira Auth
    token = HTTPBasicAuth(jira_username, jira_token)

    try:
        response = requests.get(jira_url,auth=token)
        if response.status_code == 200:
            issue_key = response.json().get("key", [])
            print(f"Jira ticket key found: {issue_key}")
            ticket_link = f"https://company.atlassian.net/browse/{issue_key}"
            print(f"Jira ticket link: {ticket_link}")
            return ticket_link
        else:
            print(f"Failed to check existing tickets. Status code: {response.status_code}")
    except Exception as e:
        print(f"Error occurred while creating Jira ticket: {e}")

if __name__ == '__main__':
    repo = os.environ.get("REPO_NAME").replace('"','')
    pr_url = os.environ.get("PR_URL").replace('"','')
    pr_url = pr_url.replace('\\','')

    jira_username = "automation_jira@company.com"
    jira_token = os.environ.get("JIRA_TOKEN_DB")

    title = f"Review for {repo} - %"
    jql_statement = f'project = DB AND (summary ~ "{title}") AND (description ~ "%{pr_url}%") AND (status != DONE)'
    print(jql_statement)

    issue_id = check_existing_ticket(jira_username, jira_token, jql_statement)
    if issue_id: 
        ticket_link = get_ticket_url(jira_username, jira_token, issue_id)
        ticket_link = ticket_link.strip()
        print(ticket_link)
    else:
        print("No existing Jira ticket found.")
        
    with open(os.environ.get("GITHUB_OUTPUT"), "a") as fh:
        print(f'jira_ticket_link={ticket_link if issue_id else ""}', file=fh)
            