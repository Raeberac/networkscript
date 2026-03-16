Network Address Monitor 
A simple, no-nonsense PowerShell script for keeping an eye on your network. I built this to have a clean, color-coded dashboard that actually tells me when things go sideways without having to dig through enterprise software.

What it does
Pings or Port Checks: If you don't provide a port, it just pings. If you do (like 80 or 443), it checks the service.

Batch Editing: You can drop a comma-separated list to remove or snooze a bunch of stuff at once.

Maintenance/Snooze: If you’re rebooting a server, just flip it to "Snooze" so it stays on the list but stops screaming at you with alerts.

Desktop Popups: If a node fails 3 times, you get a Windows popup notification.

Note: The script stores your IP list and logs in your %TEMP%\NetworkMonitor folder, so it won't clutter up your project directory.

The "Database"
If you need to manually edit your list or check the logs, look here:
C:\Users\<User>\AppData\Local\Temp\NetworkMonitor
