/// Thai translations, keyed by the exact English source string.
///
/// Not translated (shown in English): trainer, routine and move names and
/// instructions (they come from the database), live move feedback sentences
/// and camera troubleshooting text. Add a pair here to translate a string
/// that is already passed through `context.tr(...)`.
const Map<String, String> thaiStrings = {
  // Navigation
  'Home': 'หน้าหลัก',
  'History': 'ประวัติ',
  'Search': 'ค้นหา',
  'Leaderboard': 'อันดับ',
  'LeaderBoard': 'อันดับ',
  'Profile': 'โปรไฟล์',
  'Language': 'ภาษา',

  // Common
  'Cancel': 'ยกเลิก',
  'Retry': 'ลองอีกครั้ง',
  'Try again': 'ลองอีกครั้ง',
  'Back': 'กลับ',
  'Delete': 'ลบ',
  'Quit': 'ออก',
  'Resume': 'เล่นต่อ',
  'Paused': 'หยุดชั่วคราว',

  // Auth
  'Login': 'เข้าสู่ระบบ',
  'Sign up': 'สมัครสมาชิก',
  'Name': 'ชื่อ',
  'Email': 'อีเมล',
  'Password': 'รหัสผ่าน',
  'Forgot your password?': 'ลืมรหัสผ่าน?',
  'Continue with Google': 'ดำเนินการต่อด้วย Google',
  'Already have an account? ': 'มีบัญชีอยู่แล้ว? ',
  "Don't have an account? ": 'ยังไม่มีบัญชี? ',
  'Offline mode: accounts stay on this device.':
      'โหมดออฟไลน์: บัญชีจะอยู่ในเครื่องนี้เท่านั้น',
  'Check your email to confirm your account, then log in.':
      'ตรวจสอบอีเมลเพื่อยืนยันบัญชี แล้วเข้าสู่ระบบ',
  'Reset password': 'รีเซ็ตรหัสผ่าน',
  'Send link': 'ส่งลิงก์',
  'If an account exists for that email, a reset link is on its way.':
      'หากมีบัญชีสำหรับอีเมลนี้ เราได้ส่งลิงก์รีเซ็ตให้แล้ว',
  'New password': 'รหัสผ่านใหม่',
  'Repeat new password': 'ยืนยันรหัสผ่านใหม่',
  'Save password': 'บันทึกรหัสผ่าน',
  "Passwords don't match": 'รหัสผ่านไม่ตรงกัน',
  'Enter a valid email': 'กรอกอีเมลให้ถูกต้อง',
  'At least 8 characters': 'อย่างน้อย 8 ตัวอักษร',
  'Enter your name': 'กรอกชื่อของคุณ',
  'At most 40 characters': 'ไม่เกิน 40 ตัวอักษร',
  'Enter a name': 'กรอกชื่อ',
  'Use 40 characters or fewer': 'ใช้ไม่เกิน 40 ตัวอักษร',
  'Email or password is incorrect.': 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
  'An account with this email already exists.': 'อีเมลนี้มีบัญชีอยู่แล้ว',
  'That password is too weak. Use at least 8 characters with letters and numbers.':
      'รหัสผ่านง่ายเกินไป ใช้อย่างน้อย 8 ตัวอักษร ประกอบด้วยตัวอักษรและตัวเลข',
  'Please confirm your email first. Check your inbox for the link.':
      'กรุณายืนยันอีเมลก่อน ตรวจสอบลิงก์ในกล่องจดหมาย',
  "Can't reach the server. Check your connection and try again.":
      'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง',
  'Too many attempts. Please wait a moment and try again.':
      'ลองหลายครั้งเกินไป กรุณารอสักครู่แล้วลองอีกครั้ง',
  'Something went wrong. Please try again.': 'เกิดข้อผิดพลาด กรุณาลองอีกครั้ง',

  // Home, search, trainer
  'Hello, {name}': 'สวัสดี {name}',
  'Choose your trainer!': 'เลือกเทรนเนอร์ของคุณ!',
  'Search routines': 'ค้นหาท่าออกกำลังกาย',
  'Nothing found': 'ไม่พบผลลัพธ์',
  '{n} routines': '{n} ท่าออกกำลังกาย',
  ' · Recommended': ' · แนะนำ',
  '{n} moves': '{n} ท่า',
  '{n} sets': '{n} เซ็ต',
  "Couldn't update — showing saved content. Pull down to retry.":
      'อัปเดตไม่ได้ แสดงเนื้อหาที่บันทึกไว้ ดึงลงเพื่อลองใหม่',
  'Easy': 'ง่าย',
  'Medium': 'ปานกลาง',

  // History
  'No plays yet — finish a routine to see it here':
      'ยังไม่มีประวัติ เล่นให้จบหนึ่งท่าเพื่อดูที่นี่',
  'Details for this play are not available any more.':
      'ไม่มีรายละเอียดของการเล่นครั้งนี้แล้ว',

  // Leaderboard
  'Weekly': 'รายสัปดาห์',
  'All-time': 'ตลอดกาล',
  'All types': 'ทุกประเภท',
  'All': 'ทั้งหมด',
  'Dance': 'เต้น',
  'Cardio': 'คาร์ดิโอ',
  'Rank': 'อันดับ',
  'Score': 'คะแนน',
  '{name} (you)': '{name} (คุณ)',
  'Could not load the leaderboard.': 'โหลดอันดับไม่ได้',
  'No scores yet — play a routine': 'ยังไม่มีคะแนน เล่นสักท่าก่อน',

  // Summary
  'Session summary': 'สรุปการเล่น',
  'Past session': 'การเล่นที่ผ่านมา',
  'Results': 'ผลลัพธ์',
  'Score :': 'คะแนน :',
  'Move by move': 'ทีละท่า',
  'See leaderboard': 'ดูอันดับ',
  'Back to trainers': 'กลับไปหาเทรนเนอร์',
  'Saving your score…': 'กำลังบันทึกคะแนน…',
  'Saved': 'บันทึกแล้ว',
  "Will upload when you're back online": 'จะอัปโหลดเมื่อกลับมาออนไลน์',
  'Perfect groove!': 'จังหวะสมบูรณ์แบบ!',
  'Great moves!': 'ท่าเยี่ยมมาก!',
  'Getting there': 'ใกล้แล้ว',
  'Keep practicing': 'ฝึกต่อไปนะ',
  'Great': 'ยอดเยี่ยม',
  'OK': 'พอใช้',
  'Needs work': 'ต้องปรับปรุง',

  // Profile and onboarding
  'Profile saved': 'บันทึกโปรไฟล์แล้ว',
  'Goals': 'เป้าหมาย',
  'Workout styles': 'สไตล์การออกกำลังกาย',
  'Experience level': 'ระดับประสบการณ์',
  'Save changes': 'บันทึกการเปลี่ยนแปลง',
  'Sign out': 'ออกจากระบบ',
  'Delete account': 'ลบบัญชี',
  'Delete account?': 'ลบบัญชี?',
  'This permanently deletes your account, your scores and your history. It cannot be undone.': 'การดำเนินการนี้จะลบบัญชี คะแนน และประวัติของคุณอย่างถาวร และไม่สามารถย้อนกลับได้',
  'Your Fitness Goal': 'เป้าหมายการออกกำลังกายของคุณ',
  'What are your fitness goals?': 'เป้าหมายการออกกำลังกายของคุณคืออะไร?',
  'Workout Style': 'สไตล์การออกกำลังกาย',
  'What type of workout do you enjoy?': 'คุณชอบออกกำลังกายแบบไหน?',
  'Experience Level': 'ระดับประสบการณ์',
  'How would you describe your fitness experience?':
      'คุณมีประสบการณ์ออกกำลังกายระดับไหน?',
  'Personalization': 'ปรับแต่งให้คุณ',
  "Let's make it personal!": 'มาปรับให้เป็นของคุณกัน!',
  'Tell us a little about yourself so we can create a workout experience that fits you.': 'บอกเราเกี่ยวกับตัวคุณเล็กน้อย เพื่อให้เราสร้างการออกกำลังกายที่เหมาะกับคุณ',
  'Start': 'เริ่ม',
  'Next': 'ถัดไป',
  'Create My Workout Plan': 'สร้างแผนออกกำลังกายของฉัน',
  'Burn Calories': 'เผาผลาญแคลอรี',
  'Build Strength': 'เสริมความแข็งแรง',
  'Improve Fitness': 'ปรับปรุงสมรรถภาพ',
  'Improve Flexibility': 'เพิ่มความยืดหยุ่น',
  'Weight Management': 'ควบคุมน้ำหนัก',
  'Stay Healthy': 'ดูแลสุขภาพ',
  'Dance Workout': 'เต้นออกกำลังกาย',
  'Bodyweight': 'ใช้น้ำหนักตัว',
  'Stretching': 'ยืดเหยียด',
  'Beginner': 'ผู้เริ่มต้น',
  'Intermediate': 'ระดับกลาง',
  'Advanced': 'ระดับสูง',
  "I'm just getting started.": 'ฉันเพิ่งเริ่มต้น',
  'I work out occasionally.': 'ฉันออกกำลังกายเป็นครั้งคราว',
  'I know various workout techniques.': 'ฉันรู้เทคนิคการออกกำลังกายหลายแบบ',

  // Counts, durations, misc
  '1 move': '1 ท่า',
  '1 routine': '1 ท่าออกกำลังกาย',
  '{n}s': '{n} วินาที',
  '{m}m': '{m} นาที',
  '{m}m {s}s': '{m} นาที {s} วินาที',
  'or': 'หรือ',
  '{a} / {b} reps': '{a} / {b} ครั้ง',
  'Reps {a} / {b}': 'ครั้ง {a} / {b}',
  '{t} active': 'เล่นจริง {t}',
  '≈ {n} kcal (estimate)': '≈ {n} กิโลแคลอรี (ประมาณ)',
  'We could not see you for this move. Step back so your whole body is in frame.':
      'เรามองไม่เห็นคุณในท่านี้ ถอยหลังเพื่อให้เห็นทั้งตัว',
  'Nice — your form matched the trainer.': 'เยี่ยม ท่าทางของคุณตรงกับเทรนเนอร์',

  // Workout
  'Quit workout?': 'ออกจากการออกกำลังกาย?',
  'Your progress for this play will not be saved.':
      'ความคืบหน้าของการเล่นครั้งนี้จะไม่ถูกบันทึก',
  'Keep going': 'เล่นต่อ',
  'Quit workout': 'ออกจากการออกกำลังกาย',
  'Pause workout': 'หยุดการออกกำลังกายชั่วคราว',
  'Starting in {n}': 'เริ่มใน {n}',
  'Form: Good': 'ท่าทาง: ดี',
  'Form: Adjust': 'ท่าทาง: ปรับหน่อย',
  'Form: Off target': 'ท่าทาง: คลาดเคลื่อน',
  'Set {a} of {b}': 'เซ็ต {a} จาก {b}',
  '1 set left': 'เหลืออีก 1 เซ็ต',
  '{n} sets left': 'เหลืออีก {n} เซ็ต',
  'Final set': 'เซ็ตสุดท้าย',
  'Final set next': 'เซ็ตสุดท้ายถัดไป',
  'Rest': 'พัก',
  'Start next set': 'เริ่มเซ็ตถัดไปเลย',
  'Move {a} of {b}': 'ท่า {a} จาก {b}',
  'Next: {name}': 'ถัดไป: {name}',
  'Could not start the camera. Try again.': 'เปิดกล้องไม่ได้ กรุณาลองอีกครั้ง',
  'The camera stopped during your workout. Go back and start again.':
      'กล้องหยุดทำงานระหว่างออกกำลังกาย กลับไปเริ่มใหม่อีกครั้ง',

  // Playlists
  'Playlists': 'เพลย์ลิสต์',
  'My Playlists': 'เพลย์ลิสต์ของฉัน',
  'New playlist': 'สร้างเพลย์ลิสต์ใหม่',
  'Rename playlist': 'เปลี่ยนชื่อเพลย์ลิสต์',
  'Playlist name': 'ชื่อเพลย์ลิสต์',
  'Create': 'สร้าง',
  'Save': 'บันทึก',
  'Rename': 'เปลี่ยนชื่อ',
  'Remove': 'นำออก',
  'Add to playlist': 'เพิ่มเข้าเพลย์ลิสต์',
  'Added to {name}': 'เพิ่มเข้า {name} แล้ว',
  'Add workout': 'เพิ่มท่าฝึก',
  'Start playlist': 'เริ่มเล่นเพลย์ลิสต์',
  'Next in playlist': 'ท่าถัดไปในเพลย์ลิสต์',
  'Next in playlist: {name}': 'ท่าถัดไปในเพลย์ลิสต์: {name}',
  'Playlist complete!': 'เล่นจบทั้งเพลย์ลิสต์แล้ว!',
  'Playlist not found': 'ไม่พบเพลย์ลิสต์',
  'No playlists yet — create one to queue workouts':
      'ยังไม่มีเพลย์ลิสต์ กดสร้างเพื่อจัดคิวท่าออกกำลังกาย',
  'Add workouts to build your playlist':
      'กดเพิ่มท่าฝึกเพื่อจัดเพลย์ลิสต์ของคุณ',
  '1 playlist': '1 เพลย์ลิสต์',
  '{n} playlists': '{n} เพลย์ลิสต์',
};
