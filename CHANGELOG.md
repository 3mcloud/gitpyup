# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic
Versioning](https://semver.org/spec/v2.0.0.html).

Unreleased changes should be tracked under the anticipated version header, with
a date of UNRELEASED (e.g. `[1.2.0] - UNRELEASED`). This will allow the release
action to catch the correct changelog section even if the release date hasn't
been set yet.

## [1.1.1] - 2025-08-11
### Fixed
- NI pkg versions
- Missing utility function Get-StandardOutput

## [1.1.0] - 2025-08-11

### Fixed
- run-elevated-first.bat more reliable by adding '-ExecutionPolicy Bypass' 

### Changed
- Removed ability to use tls_bundle, instead conda is setup to use the system 
truststore. This is generally prefferd.

- Latest versions of National Instruments pkgs in Setup-NationalInstruments.ps1

- versioning scheme: 1 version for project instead of individual versions for 
each script

## [1.0.0] - 2025-01-06
### initial release

