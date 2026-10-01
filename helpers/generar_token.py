import os
from google_auth_oauthlib.flow import InstalledAppFlow

# Alcance exclusivo de solo lectura para Google Calendar
SCOPES = ['https://www.googleapis.com/auth/calendar.readonly']

def main():
    # Carga el archivo credentials.json descargado de la consola
    flow = InstalledAppFlow.from_client_secrets_file(
        'credentials.json', SCOPES)
    
    # Esto abrirá automáticamente una pestaña en tu navegador local
    print("Abriendo el navegador para autorizar la aplicación...")
    creds = flow.run_local_server(port=0)

    # Guarda el resultado en un archivo token.json
    with open('token.json', 'w') as token:
        token.write(creds.to_json())
    
    print("\n ¡Token generado con éxito y guardado en 'token.json'!")
    print("Este archivo contiene tu 'refresh_token' para futuras consultas automáticas.")

if __name__ == '__main__':
    main()
