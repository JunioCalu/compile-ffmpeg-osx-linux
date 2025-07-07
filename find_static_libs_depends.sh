sudo find . -name "*.a" -type f | while read lib; do
    
    # Símbolos externos não resolvidos
    #external_symbols=$(nm -u "$lib" 2>/dev/null | head -5)
    #if [ -n "$external_symbols" ]; then
    #    echo "Símbolos externos (primeiros 5):"
    #    echo "$external_symbols"
    #fi
    
    #grep -E "(libstdc|libm|libmvec|libgcc)"
    # Verificar referências específicas às bibliotecas
    lib_refs=$(nm -u "$lib")
    if [ -n "$lib_refs" ]; then
        echo "Alvo: $lib"
        echo "⚠️  Dependências das bibliotecas alvo:"
        echo "$lib_refs"
    fi  
done
