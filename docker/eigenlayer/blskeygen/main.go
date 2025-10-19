package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/Layr-Labs/crypto-libs/pkg/bn254"
	"github.com/Layr-Labs/crypto-libs/pkg/keystore"
	"github.com/Layr-Labs/crypto-libs/pkg/signing"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintf(os.Stderr, "Usage: %s <output_keystore_path> <password> [private_key_hex]\n", os.Args[0])
		os.Exit(1)
	}

	keystorePath := os.Args[1]
	password := os.Args[2]
	var privateKeyHex string
	if len(os.Args) > 3 {
		privateKeyHex = os.Args[3]
	}

	scheme := bn254.NewScheme()

	var privKey signing.PrivateKey
	var err error

	if privateKeyHex == "" {
		// Generate new key
		privKey, _, err = scheme.GenerateKeyPair()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error generating BN254 private key: %v\n", err)
			os.Exit(1)
		}
	} else {
		// Use provided key
		cleanedKey := strings.TrimPrefix(privateKeyHex, "0x")
		keyBytes, err := hex.DecodeString(cleanedKey)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error decoding private key hex: %v\n", err)
			os.Exit(1)
		}
		privKey, err = scheme.NewPrivateKeyFromBytes(keyBytes)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error creating private key from bytes: %v\n", err)
			os.Exit(1)
		}
	}

	// Save to keystore
	err = keystore.SaveToKeystoreWithCurveType(privKey, keystorePath, password, "bn254", keystore.Default())
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating keystore: %v\n", err)
		os.Exit(1)
	}

	// Get the private key bytes for output
	privateKeyBytes := privKey.Bytes()
	privateKeyHexOutput := hex.EncodeToString(privateKeyBytes)

	// Output the private key in JSON format for easy parsing
	output := map[string]string{
		"privateKey": privateKeyHexOutput,
		"keystore":   keystorePath,
	}

	jsonOutput, err := json.Marshal(output)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error marshaling output: %v\n", err)
		os.Exit(1)
	}

	fmt.Println(string(jsonOutput))
}
