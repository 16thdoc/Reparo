# Reparo in Ninja: the short version

Use **one file**: `Ninja-Embedded.ps1`.

Import it as a normal Ninja **PowerShell** script. Do not use Ninja Installer. Do
not upload helper files. Ninja only allows installer binaries there, because it has
chosen violence.

Set it to run as **SYSTEM**.

With no arguments, it only installs Reparo. It does not run updates.

## Test one computer first

Use these arguments:

```text
-Preview -Update
```

That means: “show what updates would happen, but do not do them.”

## Normal use

After the test looks sane, use:

```text
-Update
```

The script already contains a copy of Reparo. It puts that copy on the computer,
then tries GitHub for a newer copy. If GitHub is blocked, it uses the copy inside the
script and keeps going.

## Never contact GitHub

Use:

```text
-Offline true -Update
```

## Just install Reparo; do not run updates

Use:

```text
-InstallOnly true
```

Use this if GitHub must not be contacted either:

```text
-InstallOnly true -Offline true
```

## Just update the Ninja `Reparo` field

Use:

```text
-ReportOnly true
```

This only reads the installed Reparo version and puts it in the Ninja device custom
field called `Reparo`. It does not install or update anything.

## Later, when Reparo changes

1. Make the new Reparo version.
2. Run `deploy\New-NinjaEmbeddedDeployment.ps1` in the Reparo repository.
3. Import the newly made `deploy\Ninja-Embedded.ps1` into Ninja.
4. Test one machine with `-Preview -Update`.
5. Replace the old Ninja script once the test works.

Leave `-Force` alone unless you mean it. `-Update` is the normal fleet option.
