// Raiz única de testes: mantém os imports relativos dentro do módulo e
// permite que o build.zig declare apenas um artefato de teste
comptime {
    _ = @import("tests/mbr_test.zig");
    _ = @import("tests/partition_test.zig");
    _ = @import("tests/validation_test.zig");
    _ = @import("tests/report_test.zig");
    _ = @import("tests/fixtures_test.zig");
}
