# GameHarbor

GameHarbor is Utkarsh Khajuria’s local fork of NotProton for running Windows
Steam games through CrossOver on macOS. It starts from NotProton v1.2.7 and
includes the local launcher, overlay, game-file protection, and game mod work.

The desktop app is named GameHarbor. It uses the existing NotProton Steam tool
IDs, support directory, and runner configuration so games, plugins, and prefixes
keep working across the rename. The existing macSteam installation is separate
from this project.

## Build

Use the upstream build prerequisites in
[the app build workflow](.github/workflows/app.yml). With the Dobby,
bridge, and font prerequisites built, run `make app` for `out/GameHarbor.app`
or `make app-dmg` for a drag-to-Applications disk image. Run `make app-tests`
to verify the app.

## Merge upstream fixes

The `upstream` remote points to the original NotProton repository. Start from
a clean worktree and review the next release before merging it.

```sh
git fetch upstream --tags
git switch -c codex/notproton-upstream-update
git log --oneline HEAD..vX.Y.Z
git merge --no-ff vX.Y.Z
```

Replace `vX.Y.Z` with the release tag you reviewed. Rebuild and test on that
branch before merging it into local `main`. The app ships without an automatic
update feed. Its updates come from the reviewed source merges above.

## Credits and licenses

NotProton was created by **NotProtonNot** and its contributors. Thanks also
to **Selectively11** and the macSteam contributors for the separate companion
project.

- [NotProton](https://github.com/NotProtonNot/NotProton)
- [macSteam](https://github.com/crghofficial/macsteam)
- [Licensing notices](NOTICE) and [GNU GPL v3](LICENSE)

GameHarbor-specific changes to the GPL-covered app are credited to Utkarsh
Khajuria and follow GPL v3. The Steamworks code, fonts, and other dependencies
retain their own terms. Review those terms and the name before distributing a
build. GameHarbor is also the public name of an unrelated games app.
