# gitpyup
A set of PowerShell scripts to automate deployment of python applications to non-coders.

## End user usage
1. Download 3 files, *.bat, *.yml, *.ps1 All files must be in the same folder and not in a zip.
1. Right click run-elevated-firse.bat and click 'Run with Elevated Privileges' or 'Run as Administrator', allow elevation when prompted
1. Right click *.ps1 and click 'Run with PowerShell', allow  elevation when prompted and follow the prompts

## Developer Usage

### Full deployment
1. generate deploy key for your application repo
2. create config file: yourAppName.yml

```yml
#TODO add example config
```

3. upload 3 files somewhere your users can access
    1. DeployOn-*.ps1
    2. yourAppName.yml
    3. run-elevated-first.bat

### Standalone Modules
* Setup-NationalInstruments.ps1 - modify $packages array to add or remove packages, run with elevated priveleges

## FAQ 


## Contributing

### Development Guidelines
* https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines
* https://powershellfaqs.com/powershell-naming-conventions/


