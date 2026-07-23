PANEL VR
========

Uruchamianie
------------
1. Uruchom aplikację "Panel VR" ze skrótu w menu Start.
2. Po uruchomieniu serwera panel otworzy się automatycznie w domyślnej
   przeglądarce pod adresem http://127.0.0.1:8080.
3. Nie uruchamiaj kilku kopii aplikacji jednocześnie.

Połączenia
----------
- Komputer powinien mieć włączony Bluetooth i sparowany czujnik BrainAccess.
- Domyślna nazwa urządzenia EEG to "BA MINI 037".
- Klient VR i komputer z Panel VR muszą znajdować się w tej samej sieci.
- Instalator dodaje regułę Zapory systemu Windows dla sieci prywatnych.

Dane i logi
-----------
Dane aplikacji nie są zapisywane w katalogu instalacyjnym. Znajdują się w:

%LOCALAPPDATA%\NEXT\PanelVR

Katalog "logs" zawiera plik panel-vr.log. Katalog "sessions" jest przeznaczony
na dane sesji. Odinstalowanie programu nie usuwa tych danych.

Rozwiązywanie problemów
-----------------------
- Jeżeli panel się nie otworzy, sprawdź plik logs\panel-vr.log.
- Sprawdź, czy port 8080 nie jest używany przez inny program.
- W przypadku problemów z EEG sprawdź Bluetooth, nazwę urządzenia i wymagany
  pakiet Microsoft Visual C++ Runtime x64.
- Pliku PanelVR.exe nie należy przenosić poza cały katalog aplikacji.
