# repo-scanner

```
$ ruby repo-keyword-scanner-for-modified-files.rb --help
Usage: -s sourceRepoDir -t targetRepoDir
    -k, --keyword=                   Specify keyword (default:Copyright)
    -d, --detect=                    Specify keyword detection mode:detected or missing (default:missing)
    -s, --source=                    Specify source repo dir. if you want to exec as delta/new files
        --sourceGitOpt=
                                     Specify gitOpt for source repo dir.
    -t, --target=                    Specify target repo dir.
        --targetGitOpt=
                                     Specify gitOpt for target repo dir.
    -m, --mode=                      Specify mode "source&target" or "target-source" (default:source&target)
    -g, --gitPath=                   Specify target git path (regexp) if you want to limit to execute the git only
    -p, --prefix=                    Specify prefix if necessary to add for the path
    -o, --output=                    Specify report file path )
        --manifestFile=
                                     Specify manifest file (default:manifest.xml)
    -j, --numOfThreads=              Specify number of threads (default:8)
    -v, --verbose                    Enable verbose status output (default:false)

```

# Usages

```
% ruby repo-keyword-scanner-for-modified-files.rb -t ~/work/android/s -g system/
```