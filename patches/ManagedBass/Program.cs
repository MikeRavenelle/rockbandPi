// Makes ManagedBass.dll (a NuGet package YARG restores, not source we can
// patch) usable from an IL2CPP build.
//
// ManagedBass registers a "channel freed" sync with BASS for every callback
// it keeps alive, using the private static method ChannelReferences.Callback.
// IL2CPP only lets native code call a managed method that carries an
// attribute named MonoPInvokeCallback (any namespace), so without it every
// Bass.ChannelSetDSP/ChannelSetSync/CreateStream call throws
// NotSupportedException and song audio never loads.
//
// This adds that attribute, defined inside ManagedBass.dll itself. Nothing
// else changes. Running it again on a patched file does nothing.
//
//   dotnet run -- <path to ManagedBass.dll>

using Mono.Cecil;
using Mono.Cecil.Cil;

if (args.Length != 1)
{
    Console.Error.WriteLine("usage: ManagedBassIl2cppFix <ManagedBass.dll>");
    return 2;
}

const string AttributeNamespace = "ManagedBass.Il2Cpp";
const string AttributeName = "MonoPInvokeCallbackAttribute";

var path = args[0];
using var module = ModuleDefinition.ReadModule(path, new ReaderParameters { ReadWrite = true });

var callback = module.GetType("ManagedBass.ChannelReferences")?.Methods.FirstOrDefault(m => m.Name == "Callback" && m.IsStatic);
if (callback == null)
{
    Console.Error.WriteLine($"{path}: ManagedBass.ChannelReferences.Callback not found; is this a different ManagedBass version?");
    return 1;
}

if (callback.CustomAttributes.Any(a => a.AttributeType.Name == AttributeName))
{
    Console.WriteLine($"{path}: already patched");
    return 0;
}

// sealed class ManagedBass.Il2Cpp.MonoPInvokeCallbackAttribute : System.Attribute
var corlib = module.TypeSystem.CoreLibrary;
var attributeBase = new TypeReference("System", "Attribute", module, corlib);
var attributeType = new TypeDefinition(AttributeNamespace, AttributeName,
    TypeAttributes.NotPublic | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit, attributeBase);

var ctor = new MethodDefinition(".ctor",
    MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName | MethodAttributes.RTSpecialName,
    module.TypeSystem.Void);
var baseCtor = new MethodReference(".ctor", module.TypeSystem.Void, attributeBase) { HasThis = true };
var il = ctor.Body.GetILProcessor();
il.Emit(OpCodes.Ldarg_0);
il.Emit(OpCodes.Call, baseCtor);
il.Emit(OpCodes.Ret);
attributeType.Methods.Add(ctor);
module.Types.Add(attributeType);

callback.CustomAttributes.Add(new CustomAttribute(ctor));
module.Write();

Console.WriteLine($"{path}: added [MonoPInvokeCallback] to ManagedBass.ChannelReferences.Callback");
return 0;
