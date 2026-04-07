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
}
