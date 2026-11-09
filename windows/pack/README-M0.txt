Verdandi Windows, milestone M0 (no product yet).

What is in this folder
  M0-REPORT.md          the result of every step of the build run: read this first
  logs\                 the full log of every step
  inventory.tsv         which source files of norns compile on their own with MinGW (the porting work list)
  sc-win64.zip          SuperCollider 3.14.1 built for Windows without Qt (sclang, scsynth, plug-ins, class library)
  norns-sc\             norns's own SuperCollider classes
  verdandi-test.cmd     double-click to repeat the SuperCollider test on your own PC
  m0-job.scd, sc-smoke\   used by verdandi-test.cmd (sc-smoke switches norns's own server boot off for the test)

Safe to run: verdandi-test.cmd does not install anything, needs no admin rights, opens no audio device, plays no sound and
touches nothing outside this folder. Windows may warn about files from the internet: right-click the downloaded .zip,
Properties, tick "Unblock", OK, and only then unpack it. If SmartScreen still warns about verdandi-test.cmd, choose More info, Run anyway
(it is a plain text file you can read first; the files are not signed in this stage).

After it ran, send back: M0-LOCAL-REPORT.txt (made next to the cmd file) and, if you did not do so already, M0-REPORT.md from this folder.
