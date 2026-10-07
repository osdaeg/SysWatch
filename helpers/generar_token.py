import os
from google_auth_oauthlib.flow import InstalledAppFlow

# Combined read-only scopes for Calendar and Tasks
SCOPES = [
    'https://www.googleapis.com/auth/calendar.readonly',
    'https://www.googleapis.com/auth/tasks.readonly'
]

def main():
    flow = InstalledAppFlow.from_client_secrets_file('credentials.json', SCOPES)
    print("Opening browser for authorization... / Abriendo el navegador para autorizar...")
    creds = flow.run_local_server(port=0)

    with open('token.json', 'w') as token:
        token.write(creds.to_json())
    
    print("\nToken generated successfully! Look for your refresh_token inside 'token.json'.")
    print("¡Token generado con éxito! Busca tu 'refresh_token' dentro de 'token.json'.")

if __name__ == '__main__':
    main()

