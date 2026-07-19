import 'package:autoshare/Customer/customer_home_page.dart';
import 'package:autoshare/Driver/driver_home_page.dart';
import 'package:autoshare/Login&Signup/login_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoshare/services/api_service.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});
  @override
  State<RegistrationPage> createState() => _RegistrationPage();
}

class _RegistrationPage extends State<RegistrationPage> {
  String selectedItem = 'Customer';
  String selectedGender = 'Other';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController(); 
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _licenseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          height: 650,
          width: 375,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 254, 187, 38),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    //mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        'Create Account',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 42,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 48),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          labelStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500),
                          border: UnderlineInputBorder(),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.black, width: 2),
                          ),
                          hintText: 'Enter your full name',
                          hintStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w500),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: Icon(Icons.person, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Phone field — for both
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          labelStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500),
                          border: UnderlineInputBorder(),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.black, width: 2),
                          ),
                          hintText: 'Enter your phone number',
                          hintStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w500),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: Icon(Icons.phone, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Gender',
                          prefixIcon: Icon(Icons.person, color: Colors.black),
                        ),
                        initialValue: selectedGender,
                        icon: const Icon(Icons.arrow_drop_down),
                        style: const TextStyle(color: Colors.black),
                        dropdownColor: Colors.white,
                        onChanged: (String? newValue) {
                          setState(() => selectedGender = newValue!);
                        },
                        items: ['M', 'F', 'Other'].map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                              value == 'M' ? 'Male' : value == 'F' ? 'Female' : 'Other',
                              style: const TextStyle(color: Colors.black),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // Vehicle & License — only show for driver
                      if (selectedItem == 'Driver') ...[
                        TextField(
                          controller: _vehicleController,
                          decoration: InputDecoration(
                            labelText: 'Vehicle Number',
                            labelStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500),
                            border: UnderlineInputBorder(),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.black, width: 2),
                            ),
                            hintText: 'e.g. GJ01MN1234',
                            hintStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w500),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            prefixIcon: Icon(Icons.directions_car, color: Colors.black),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _licenseController,
                          decoration: InputDecoration(
                            labelText: 'License Number',
                            labelStyle: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w500),
                            border: UnderlineInputBorder(),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.black, width: 2),
                            ),
                            hintText: 'Enter license number',
                            hintStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w500),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                            prefixIcon: Icon(Icons.badge, color: Colors.black),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w500),
                          border: UnderlineInputBorder(),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          hintText: 'Enter your email',
                          hintStyle: TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w500),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: Icon(
                            Icons.mail,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w500),
                          border: UnderlineInputBorder(),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          hintText: 'Enter your password',
                          hintStyle: TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w500),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: Icon(
                            Icons.mail,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: selectedItem,
                        icon: Icon(Icons.arrow_drop_down),
                        style: TextStyle(color: Colors.black),
                        underline: Container(height: 2, color: Colors.black),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedItem = newValue!;
                          });
                        },
                        items: ['Customer', 'Driver']
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            // Basic validation
                            if (_emailController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Please enter email'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            if (_passwordController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Please enter password'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            if (_nameController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Please enter name'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            if (_phoneController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Please enter phone'), backgroundColor: Colors.red),
                              );
                              return;
                            }

                            try {
                              Map<String, dynamic> result;

                              if (selectedItem == 'Customer') {
                                // Call customer registration API
                                result = await ApiService.registerCustomer(
                                  name: _nameController.text,
                                  email: _emailController.text,
                                  phone: _phoneController.text,
                                  password: _passwordController.text,
                                  gender: selectedGender,
                                );
                              } else {
                                // Call driver registration API
                                result = await ApiService.registerDriver(
                                  name: _nameController.text,
                                  email: _emailController.text,
                                  phone: _phoneController.text,
                                  password: _passwordController.text,
                                  vehicleNumber: _vehicleController.text,
                                  licenseNumber: _licenseController.text,
                                );
                              }

                              // Save user info to SharedPreferences for easy access
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('isLoggedIn', true);
                              await prefs.setString('userType', result['role']);
                              await prefs.setString('userName', result['name']);
                              await prefs.setString('userId', result['user_id']);

                              if (!context.mounted) return;

                              // Navigate based on role
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => result['role'] == 'customer'
                                      ? const CustomerHomePage()
                                      : const DriverHomePage(),
                                ),
                                (route) => false,
                              );

                            } catch (e) {
                              // Show error from API (e.g. "Email already registered")
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString().replaceAll('Exception: ', '')),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(0))),
                          child: Text(
                            'Create Account',
                            style: TextStyle(
                              color: const Color.fromARGB(255, 254, 187, 38),
                              fontWeight: FontWeight.w500,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 48),
                      Text(
                        'Already Have an Account?',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LoginPage(),
                            ),
                            (Route<dynamic> route) => false,
                          );
                        },
                        child: Text(
                          'Login',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
