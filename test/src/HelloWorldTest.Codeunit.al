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

    [Test]
    procedure FarewellWithName_ReturnsPersonalisedFarewell()
    var
        HelloWorld: Codeunit "Hello World";
        Result: Text;
    begin
        // [GIVEN] a name
        // [WHEN] Farewell is called
        Result := HelloWorld.Farewell('Stefan');
        // [THEN] the result is the personalised farewell
        LibraryAssert.AreEqual('Goodbye, Stefan!', Result, 'Farewell should return a personalised farewell');
    end;

    [Test]
    procedure FarewellWithEmptyName_ReturnsGenericFarewell()
    var
        HelloWorld: Codeunit "Hello World";
        Result: Text;
    begin
        // [GIVEN] an empty name
        // [WHEN] Farewell is called
        Result := HelloWorld.Farewell('');
        // [THEN] the result is the generic farewell
        LibraryAssert.AreEqual('Goodbye, world!', Result, 'Farewell should fall back to a generic farewell when name is empty');
    end;

    [Test]
    procedure LengthWithName_ReturnsLengthOfPersonalisedGreeting()
    var
        HelloWorld: Codeunit "Hello World";
        Result: Integer;
    begin
        // [GIVEN] a name
        // [WHEN] Length is called
        Result := HelloWorld.Length('Stefan');
        // [THEN] the result equals the length of the personalised greeting
        LibraryAssert.AreEqual(StrLen(HelloWorld.Greet('Stefan')), Result, 'Length should return the length of the personalised greeting');
    end;

    [Test]
    procedure LengthWithEmptyName_ReturnsLengthOfGenericGreeting()
    var
        HelloWorld: Codeunit "Hello World";
        Result: Integer;
    begin
        // [GIVEN] an empty name
        // [WHEN] Length is called
        Result := HelloWorld.Length('');
        // [THEN] the result equals the length of the generic greeting
        LibraryAssert.AreEqual(StrLen(HelloWorld.Greet('')), Result, 'Length should return the length of the generic greeting when name is empty');
    end;
}
