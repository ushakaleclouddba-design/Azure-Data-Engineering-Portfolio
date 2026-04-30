-- =============================================================================
-- UshaAg22-Phase5-Step06-Backups-Loans_OnPrem.sql
-- =============================================================================
-- Phase:    5 — Create UshaAg22MI + Banking Schema
-- Steps:    5.6 + 5.7 — Take initial full backup and log backup of Loans_OnPrem
-- Run on:   Node3 in SSMS
-- Date:     April 28, 2026
-- =============================================================================
--
-- PURPOSE
-- -------
-- Takes a full + log backup of Loans_OnPrem to C:\Backup. Both required
-- before adding the database to UshaAg22MI in Step 5.8.
--
-- WHY BOTH BACKUPS
-- ----------------
-- Even though SEEDING_MODE = AUTOMATIC streams data directly between
-- replicas, SQL Server's CREATE AVAILABILITY GROUP requires that the
-- database has at least one full backup on record. Adding a log backup
-- afterwards establishes an uninterrupted log chain — silences AG join
-- warnings and satisfies MI Link's prerequisites for Day 2.
--
-- BACKUP OPTIONS EXPLAINED
-- ------------------------
-- INIT      — Overwrite the backup file if it exists.
-- COMPRESSION — Compress the backup. Reduces disk footprint and speeds
--             up the AG seeding fallback path. Default in SQL 2022.
-- FORMAT    — Reformat the backup media (creates a fresh media set).
-- CHECKSUM  — Verify checksums during backup. Catches I/O errors.
-- STATS = 5 — Progress reports every 5%.
-- =============================================================================

USE master;
GO

-- ---------------------------------------------------------------------
-- 5.6 — Full backup
-- ---------------------------------------------------------------------
PRINT 'Step 5.6 - Starting full backup of Loans_OnPrem...';

BACKUP DATABASE Loans_OnPrem
    TO DISK = 'C:\Backup\Loans_OnPrem_Full.bak'
    WITH 
        INIT,
        FORMAT,
        COMPRESSION,
        CHECKSUM,
        STATS = 5,
        NAME = 'Loans_OnPrem-Full Database Backup',
        DESCRIPTION = 'Initial full backup before AG join (UshaAg22MI)';
GO

PRINT 'Step 5.6 complete.';

-- ---------------------------------------------------------------------
-- 5.7 — Log backup
-- ---------------------------------------------------------------------
PRINT 'Step 5.7 - Starting log backup of Loans_OnPrem...';

BACKUP LOG Loans_OnPrem
    TO DISK = 'C:\Backup\Loans_OnPrem_Log.trn'
    WITH 
        INIT,
        FORMAT,
        COMPRESSION,
        CHECKSUM,
        STATS = 10,
        NAME = 'Loans_OnPrem-Log Backup',
        DESCRIPTION = 'Initial log backup before AG join (UshaAg22MI)';
GO

PRINT 'Step 5.7 complete.';

-- Verify both backups exist on disk
EXEC xp_fileexist 'C:\Backup\Loans_OnPrem_Full.bak';
EXEC xp_fileexist 'C:\Backup\Loans_OnPrem_Log.trn';

-- Show backup history
SELECT 
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type
    END AS BackupType,
    bs.backup_start_date,
    bs.backup_finish_date,
    CAST(bs.backup_size  / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS BackupSizeMB,
    CAST(bs.compressed_backup_size / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS CompressedMB,
    bmf.physical_device_name AS BackupFile
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name = 'Loans_OnPrem'
ORDER BY bs.backup_finish_date DESC;
GO
