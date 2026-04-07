// Example test codeunit. Copilot should follow this pattern when adding
// tests for new features: codeunit IDs in 50100..50199, [Test] procedures,
// LibraryAssert for assertions.
codeunit 50100 "Hello World Test"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        LibraryAssert: Codeunit "Library Assert";

    [Test]
    procedure GreetWithName_ReturnsPersonalisedGreeting()
    var
        HelloWorld: Codeunit "Hello World";
        Result: Text;
    begin
        // [GIVEN] a name
        // [WHEN] Greet is called
        Result := HelloWorld.Greet('Stefan');
        // [THEN] the result is the personalised greeting
        LibraryAssert.AreEqual('Hello, Stefan!', Result, 'Greet should return a personalised greeting');
    end;

    [Test]
    procedure GreetWithEmptyName_ReturnsGenericGreeting()
    var
        HelloWorld: Codeunit "Hello World";
        Result: Text;
    begin
        // [GIVEN] an empty name
        // [WHEN] Greet is called
        Result := HelloWorld.Greet('');
        // [THEN] the result is the generic greeting
        LibraryAssert.AreEqual('Hello, world!', Result, 'Greet should fall back to a generic greeting when name is empty');
    end;
}
