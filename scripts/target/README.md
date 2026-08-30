# GarStreamRx Luckfox Lyra Plus target

This directory owns the RK3506 cross-build, runtime closure, SPI kernel
modules, Product Device Tree overlay, target configuration, and artifact
packaging for GarStreamRx. Reusable board lifecycle support remains in the
`gar-tools` Target Pack.

The top-level RK3506 scripts are compatibility dispatchers. New target work
must be implemented in this capsule.
