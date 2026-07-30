PANEL VR
========

Przeznaczenie
-------------
Panel VR jest lokalną aplikacją badawczą do prowadzenia i zapisywania
nadzorowanych sesji VR. Wyświetla obraz z gogli, punkt śledzenia wzroku oraz
surowy sygnał EEG. Program nie jest zwalidowanym wyrobem medycznym i nie
wyznacza wskaźników diagnostycznych EEG.

Wymagania
---------
- Windows 10 lub 11 w wersji x64.
- Czujnik BrainAccess MINI.
- Adapter BrainAccess USB BLE.
- Pakiet Microsoft Visual C++ Redistributable x64.
- Komputer i gogle VR w tej samej prywatnej sieci lokalnej.

Do pracy produkcyjnej należy używać adaptera BrainAccess USB BLE. Jeżeli
komputer ma również wbudowany Bluetooth i połączenie jest niestabilne, należy
wyłączyć wbudowany adapter w Menedżerze urządzeń. BrainAccess Board i inne
programy korzystające z czujnika muszą być zamknięte.

Uruchamianie
------------
1. Podłącz adapter BrainAccess USB BLE.
2. Włącz czujnik EEG. Czujnik nie może być w tym czasie ładowany.
3. Połącz komputer i gogle VR z tą samą prywatną siecią.
4. Uruchom "Panel VR" ze skrótu w menu Start.
5. Panel otworzy się automatycznie w domyślnej przeglądarce pod adresem
   http://127.0.0.1:8080.
6. Uruchom aplikację VR i poczekaj na automatyczne wykrycie serwera.
7. Przed utworzeniem sesji sprawdź aktywność backendu, EEG, VR i ET.

Nie należy uruchamiać kilku kopii aplikacji jednocześnie.

Sesja
-----
1. Podaj identyfikator pacjenta, preferowaną rękę i opcjonalne notatki.
2. Utwórz sesję.
3. W trakcie sesji można sterować sceną VR i dodawać obserwowane zdarzenia.
4. Zakończ sesję z poziomu panelu.
5. Pobierz raport JSON i archiwum ZIP z surowymi danymi.

Tylko jedna sesja może być aktywna. Po nieoczekiwanym zamknięciu programu
niedokończona sesja zostanie oznaczona jako przerwana i pokazana po ponownym
uruchomieniu.

Połączenia
----------
Serwer HTTP i WebSocket korzysta domyślnie z portu TCP 8080. Gogle wykrywają
serwer przez komunikaty UDP na porcie 15000. Instalator dodaje regułę Zapory
systemu Windows dla programu Panel VR w sieci prywatnej.

Diody i sparowanie Bluetooth nie potwierdzają przepływu danych. Wskaźnik EEG w
panelu jest aktywny tylko wtedy, gdy aplikacja otrzymuje nowe próbki.

Dane i logi
-----------
Dane aplikacji nie są zapisywane w katalogu instalacyjnym. Znajdują się w:

%LOCALAPPDATA%\NEXT\PanelVR

Najważniejsze elementy:

- logs\panel-vr.log - główny plik logu;
- sessions.sqlite3 - metadane i liczniki sesji;
- sessions\<identyfikator_sesji> - surowe pliki NDJSON;
- exports - pliki tymczasowe generowane podczas eksportu.

Odinstalowanie programu nie usuwa tych danych. Zawierają one identyfikatory,
notatki i sygnały badawcze, dlatego należy objąć je zasadami dostępu, kopii
zapasowych, retencji i bezpiecznego usuwania.

Rozwiązywanie problemów
-----------------------
Panel nie otwiera się:
- sprawdź plik %LOCALAPPDATA%\NEXT\PanelVR\logs\panel-vr.log;
- sprawdź, czy port 8080 nie jest zajęty;
- otwórz http://127.0.0.1:8080/api/health.

Gogle VR nie łączą się:
- sprawdź, czy sieć Windows ma profil prywatny;
- sprawdź, czy komputer i gogle są w tej samej podsieci;
- sprawdź regułę Zapory systemu Windows "Panel VR";
- w pliku logu odszukaj adres "Beacon advertising".

EEG nie przesyła danych:
- sprawdź adapter BrainAccess USB BLE;
- zamknij BrainAccess Board;
- sprawdź nazwę czujnika, domyślnie "BA MINI 037";
- odłącz ładowanie czujnika;
- sprawdź pakiet Microsoft Visual C++ Redistributable x64;
- otwórz /api/health i sprawdź pola eeg_status oraz eeg_error.

Stała niebieska dioda oznacza połączenie BLE, ale nie gwarantuje napływu próbek.
Po poprawnym podłączeniu wykresy wszystkich czterech kanałów powinny zmieniać
się przez cały czas trwania sesji.

Pliku PanelVR.exe nie należy przenosić poza cały katalog aplikacji.
