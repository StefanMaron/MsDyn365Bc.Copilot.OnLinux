// Trivial example codeunit. Copilot should treat this as a structural
// model — extend it, replace it, or add new codeunits alongside it.
codeunit 50000 "Hello World"
{
    procedure Greet(Name: Text): Text
    begin
        if Name = '' then
            exit('Hello, world!');
        exit(StrSubstNo('Hello, %1!', Name));
    end;

    procedure Farewell(Name: Text): Text
    begin
        if Name = '' then
            exit('Goodbye, world!');
        exit(StrSubstNo('Goodbye, %1!', Name));
    end;

    procedure Length(Name: Text): Integer
    begin
        exit(StrLen(Greet(Name)));
    end;
}
