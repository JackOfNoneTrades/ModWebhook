# ModWebhook
Discord webhook script for new Modrinth and Curseforge projects.

## Usage
* Copy `.env-example` into `.env`.
* Fill it with a Modrinth personal acess token, a CurseForge [developer console](https://console.curseforge.com/) API token, and optionally change other variables.
* Create a Discord webhook, copy its url, and paste it into a file named `$WEBHOOK_LIST` (`webhooks.txt` by default). You can dispatch content to as many dispatchers as you want, simply put their urls on new lines inside that file.
* Finally, run `curse.sh` and `modrinth.sh`. You can do this with cron.

<img width="420" height="453" alt="image" src="https://github.com/user-attachments/assets/a6d79d63-ebc4-4d84-a64e-a894bae6acb0" />
