# Matrice de fiabilitate și securitate — DataMover 2.16.0 (candidat)

Stare la 2026-09-26. **PASS** = verificat automat, reproductibil, cu comanda de
mai jos. **FAIL** = defect cunoscut, nerezolvat. **NEVERIFICAT** = nu există
dovadă; nu se presupune că funcționează.

Comenzi:
- `scripts/preflight.sh` — build + toate testele macOS (XCTest) + verificări C# (CoreChecks)
- `scripts/preflight.sh --volumes` — volume reale temporare (imagini de disc APFS/exFAT, șterse la final)
- `scripts/preflight.sh --vm` — `DataMover.WinChecks` pe Windows 11 real (NTFS), fără interfață

Toate testele lucrează doar în directoare temporare, cu date sintetice.

## Integritate și erori

| Caz | macOS | Windows | Dovadă |
|---|---|---|---|
| Disc plin în timpul copierii | PASS | NEVERIFICAT | `VolumeFaultTests.testDiskFullMidTransferIsNeverConfirmed` (APFS 20 MB real); pe Windows cere VHD = drepturi de administrator |
| Spațiu insuficient cunoscut la pornire | PASS | PASS (logică) | `testSpaceShortfallBlocksStartBeforeAnyWrite`; Windows: aceeași regulă, fără volum real mic |
| Spațiu liber pe exFAT | PASS (după reparație) | PASS | macOS raporta 0 octeți liberi pe exFAT — reparat în 2.16.0, regresie în `testExFATTransferAndResume` |
| Acces refuzat la destinație | PASS | PASS | `testReadOnlyDestinationGivesPartialFailure`, `testWriteFailureOnReadOnlyDestination` |
| Fișier sursă ilizibil / blocat de alt proces | PASS | PASS (după reparație) | `testUnreadableSourceFileIsNeverConfirmed`; WinChecks „fișier blocat” (defect găsit și reparat: fire blocate + `.dmpart` orfan) |
| Destinație deconectată în timpul transferului | PASS (simulat) | PASS (real, `subst` scos la 10 %) | `testVanishedDestinationIsUnavailableAndNotRecreated`; WinChecks „deconectare” |
| Unitate lipsă la pornire | PASS | PASS | preflight `destinationMissing` |
| Checksum diferit / sursă modificată în timpul copierii | PASS | PASS | `testSourceChangeIsMismatchAndPartialNeverPromoted`, CoreChecks |
| Flush eșuat | PASS | PASS (logică) | `testCopyWithFailingFlushIsNotConfirmed`, `testRealFullFsyncErrorIsNotMaskedByFallback` |
| Checkpoint corupt / vechi (schema < 3) / alt algoritm | PASS | PASS | `testCorruptCheckpointIsRejected`, `testSchema2IsRejected`, `testChangedAlgorithmIsRejected`, CoreChecks |
| Aceleași metadate, alți octeți (card diferit) | PASS | PASS | `testSameMetadataDifferentBytesIsRecopied`; WinChecks „reluare byte-safe” |
| Oprire bruscă → reluare (simulată) | PASS | PASS | `testResumeAfterSimulatedCrashCleansPartialsAndVerifies` |
| Oprire bruscă reală a procesului / pană de curent | NEVERIFICAT | NEVERIFICAT | necesită kill -9 în timpul scrierii pe hardware real |
| Anulare în mijlocul unui fișier | PASS | PASS | `testCancelMidFileLeavesNeitherFinalNorPartial`, CoreChecks |
| Nume Unicode (NFC/NFD, diacritice, CJK) | PASS | PASS (NTFS) | `testUnicodeAndLongPathNames`, WinChecks |
| Căi lungi (> 260 caractere pe Windows) | PASS | PASS (368 car.) | idem; defect găsit și reparat în `MoveFileEx` |
| Fișiere goale, 400 de fișiere mici | PASS | PASS (logică) | `testManySmallFilesAndEmptyFiles` |
| Două destinații, rezultat parțial | PASS | PASS | `testMixedResultIsPartialFailureAndBlocksEject`, WinChecks |
| Coliziune de nume între surse (majuscule/NFC) | PASS | PASS | `testSourceNameCollisionIsBlockedBeforeAnyWrite`, WinChecks |
| exFAT | PASS (imagine reală) | NEVERIFICAT | `testExFATTransferAndResume` |
| SMB / volum de rețea | NEVERIFICAT | NEVERIFICAT | necesită server izolat |
| Card real în cititor, scos fizic | NEVERIFICAT | NEVERIFICAT | necesită hardware |

## Securitate

| Caz | macOS | Windows | Dovadă |
|---|---|---|---|
| Destinația în sursă / sursa în destinație / destinații suprapuse | PASS | PASS | `testOverlapsAreBlocking`, `testDuplicateAndNestedDestinations`, CoreChecks |
| Prefix de text nu înseamnă „în interior” (`A` vs `AB`) | PASS | PASS | `testPrefixIsNotContainment`, CoreChecks |
| Symlink / junction la destinație care iese din țintă | PASS | PASS (junction) | `testSymlinkedDestinationFolderCannotEscapeTarget`; WinChecks junction |
| Symlink de fișier în sursă | PASS (copiază ținta) | NEVERIFICAT | symlink-urile Windows cer privilegiu; junction-urile sunt acoperite |
| Path traversal (`..` în căi relative) | PASS (prin construcție) | PASS (prin construcție) | căile relative vin din enumerarea sursei; garda `isInsideTarget` refuză orice ieșire din țintă |
| Secrete în jurnale și export | PASS | PASS | `testSecretsAreRedacted`, `testExportExcludesMediaSecretsAndPaths`, CoreChecks, WinChecks export |
| Căi personale în export (anonimizate implicit) | PASS | PASS | idem |
| Jurnal nescriibil nu afectează transferul | PASS | PASS (logică) | `testBrokenLoggerDoesNotAffectTransfer`, `testUnwritableDirectoryFailsSafely` |

## Interfață Windows

| Verificare | Stare | Dovadă |
|---|---|---|
| Pregătire / Transfer / Rezultat / Blocat / Setări, dark și light | PASS (randat) | capturi randate de aplicație la DPI 96/144, 1024×700 → 1600×1000 |
| Navigare doar din tastatură, cititor de ecran | NEVERIFICAT | elementele au nume de automatizare; ordinea Tab nu a fost parcursă |
| Scalare reală 150 % a sistemului (nu doar randare la 144 DPI) | NEVERIFICAT | |

## Concluzie

Există cazuri critice **NEVERIFICAT** (oprire bruscă reală, hardware real scos
fizic, SMB, disc plin pe Windows). Produsul **nu** se declară „sigur pentru
producție” până la închiderea lor.
